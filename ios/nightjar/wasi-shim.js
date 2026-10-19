// wasi-shim.js — the Blacksite kernel's
// WASI preview1 syscall surface.
//
// A WebAssembly guest compiled against
// wasi-libc believes it is a Linux
// process. Every syscall it makes lands
// here, and here is where the kernel's
// law applies: the guest sees exactly
// the filesystem the kernel staged for
// it (its preopen), its output streams
// to the console through the host, its
// writes land back in the house files
// the moment a file closes, and its
// only way out is proc_exit, which the
// host hears. Paths cannot escape the
// root: resolution clamps at "/", the
// way a chroot does.
//
// Host contract (Swift in the app, a
// mock on the bench):
//   host.post({t:'out', fd, s})     —
//     stdout/stderr, already decoded
//   host.post({t:'write', path, b64})
//   host.post({t:'mkdir'|'unlink'|
//     'rmdir', path})
//   host.post({t:'rename', from, to})
//   host.post({t:'exit', code})
//
// startGuest(config, bytes) with
// config = { argv, env, cwd, stdin,
//            files: {path: {d, b64}} }

'use strict';

class WasiExit extends Error {
  constructor(code) {
    super('wasi exit ' + code);
    this.code = code;
  }
}

function b64encode(bytes) {
  let bin = '';
  const CH = 0x8000;
  for (let i = 0; i < bytes.length; i += CH) {
    bin += String.fromCharCode.apply(
      null, bytes.subarray(i, i + CH));
  }
  return btoa(bin);
}

function b64decode(text) {
  const bin = atob(text);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) {
    out[i] = bin.charCodeAt(i);
  }
  return out;
}

const ERR = {
  SUCCESS: 0, BADF: 8, EXIST: 20,
  INVAL: 28, IO: 29, ISDIR: 31,
  NAMETOOLONG: 37, NOENT: 44,
  NOSYS: 52, NOTDIR: 54, NOTEMPTY: 55,
  PERM: 63,
};

const FT = {
  UNKNOWN: 0, CHAR: 2, DIR: 3, FILE: 4,
};

function makeWasi(config, host) {
  const enc = new TextEncoder();
  const files = new Map();
  files.set('/', {
    dir: true, data: new Uint8Array(0),
    mtime: Date.now(),
  });
  for (const path of Object.keys(
      config.files || {})) {
    const f = config.files[path];
    files.set(path, {
      dir: !!f.d,
      data: f.b64 ? b64decode(f.b64)
                  : new Uint8Array(0),
      mtime: f.mtime || Date.now(),
      stagedEmpty: !!f.stagedEmpty,
    });
  }

  let memory = null;
  const u8 = () => new Uint8Array(memory.buffer);
  const dv = () => new DataView(memory.buffer);

  function readStr(ptr, len) {
    return new TextDecoder().decode(
      u8().subarray(ptr, ptr + len));
  }

  const stdindata = enc.encode(config.stdin || '');
  const fds = new Map();
  fds.set(0, { kind: 'stdin', pos: 0 });
  fds.set(1, { kind: 'stdout' });
  fds.set(2, { kind: 'stderr' });
  fds.set(3, { kind: 'dir', path: '/' });
  let nextFd = 4;
  const streamDecoders = {
    1: new TextDecoder(),
    2: new TextDecoder(),
  };

  function normalize(path, base) {
    const parts = [];
    if (!path.startsWith('/')) {
      for (const seg of base.split('/')) {
        if (seg) parts.push(seg);
      }
    }
    for (const seg of path.split('/')) {
      if (seg === '' || seg === '.') continue;
      if (seg === '..') { parts.pop(); continue; }
      parts.push(seg);
    }
    return '/' + parts.join('/');
  }

  function parentOf(p) {
    const i = p.lastIndexOf('/');
    return i <= 0 ? '/' : p.slice(0, i);
  }

  function baseName(p) {
    return p.slice(p.lastIndexOf('/') + 1);
  }

  function childrenOf(dirPath) {
    const names = [];
    for (const key of files.keys()) {
      if (key === dirPath) continue;
      if (parentOf(key) === dirPath) {
        names.push(baseName(key));
      }
    }
    names.sort();
    return names;
  }

  function inodeOf(path) {
    let h = 7;
    for (let i = 0; i < path.length; i++) {
      h = (h * 31 + path.charCodeAt(i)) >>> 0;
    }
    return h + 2;
  }

  function writeFilestat(ptr, path, entry) {
    const d = dv();
    d.setBigUint64(ptr + 0, 1n, true);
    d.setBigUint64(ptr + 8,
      BigInt(inodeOf(path)), true);
    d.setUint8(ptr + 16,
      entry.dir ? FT.DIR : FT.FILE);
    d.setBigUint64(ptr + 24, 1n, true);
    d.setBigUint64(ptr + 32,
      BigInt(entry.dir ? 0
             : entry.data.length), true);
    const ns = BigInt(
      Math.floor(entry.mtime)) * 1000000n;
    d.setBigUint64(ptr + 40, ns, true);
    d.setBigUint64(ptr + 48, ns, true);
    d.setBigUint64(ptr + 56, ns, true);
  }

  function flushFile(fdobj) {
    if (fdobj.kind === 'file' && fdobj.dirty) {
      const entry = files.get(fdobj.path);
      if (entry) {
        host.post({
          t: 'write', path: fdobj.path,
          b64: b64encode(entry.data),
        });
      }
      fdobj.dirty = false;
    }
  }

  function resolveDirFd(dirfd, path) {
    const base = dirfd === 3 ? '/'
      : (fds.get(dirfd) || {}).path;
    if (base === undefined) return null;
    return normalize(path, base);
  }

  const wasi = {
    args_sizes_get(argcPtr, bufSizePtr) {
      const d = dv();
      let total = 0;
      for (const a of config.argv) {
        total += enc.encode(a).length + 1;
      }
      d.setUint32(argcPtr, config.argv.length, true);
      d.setUint32(bufSizePtr, total, true);
      return 0;
    },
    args_get(argvPtr, bufPtr) {
      const d = dv();
      let at = bufPtr;
      config.argv.forEach((a, i) => {
        d.setUint32(argvPtr + i * 4, at, true);
        const bytes = enc.encode(a);
        u8().set(bytes, at);
        u8()[at + bytes.length] = 0;
        at += bytes.length + 1;
      });
      return 0;
    },
    environ_sizes_get(countPtr, sizePtr) {
      const pairs = Object.keys(config.env || {})
        .map(k => k + '=' + config.env[k]);
      let total = 0;
      for (const p of pairs) {
        total += enc.encode(p).length + 1;
      }
      const d = dv();
      d.setUint32(countPtr, pairs.length, true);
      d.setUint32(sizePtr, total, true);
      return 0;
    },
    environ_get(envPtr, bufPtr) {
      const pairs = Object.keys(config.env || {})
        .map(k => k + '=' + config.env[k]);
      const d = dv();
      let at = bufPtr;
      pairs.forEach((p, i) => {
        d.setUint32(envPtr + i * 4, at, true);
        const bytes = enc.encode(p);
        u8().set(bytes, at);
        u8()[at + bytes.length] = 0;
        at += bytes.length + 1;
      });
      return 0;
    },

    fd_close(fd) {
      const o = fds.get(fd);
      if (!o) return ERR.BADF;
      if (o.kind === 'file') flushFile(o);
      fds.delete(fd);
      return 0;
    },
    fd_fdstat_get(fd, bufPtr) {
      const o = fds.get(fd);
      if (!o) return ERR.BADF;
      const d = dv();
      const type = o.kind === 'dir' ? FT.DIR
        : o.kind === 'file' ? FT.FILE : FT.CHAR;
      d.setUint8(bufPtr + 0, type);
      d.setUint16(bufPtr + 2,
        o.append ? 1 : 0, true);
      // Rights: honest subsets — stdio
      // reads or writes, files work,
      // directories open paths.
      let rights;
      if (o.kind === 'stdin') rights = 1n << 1n;
      else if (o.kind === 'stdout' ||
               o.kind === 'stderr') {
        rights = 1n << 6n;
      } else if (o.kind === 'dir') {
        rights = (1n << 9n) | (1n << 10n)
          | (1n << 13n) | (1n << 14n)
          | (1n << 16n) | (1n << 17n)
          | (1n << 18n) | (1n << 20n)
          | (1n << 25n) | (1n << 26n)
          | (1n << 21n);
      } else {
        rights = (1n << 1n) | (1n << 2n)
          | (1n << 5n) | (1n << 6n)
          | (1n << 21n) | (1n << 22n);
      }
      d.setBigUint64(bufPtr + 8, rights, true);
      d.setBigUint64(bufPtr + 16, rights, true);
      return 0;
    },
    fd_fdstat_set_flags(fd, flags) {
      const o = fds.get(fd);
      if (!o) return ERR.BADF;
      // fdflags: APPEND is bit 0; the
      // rest (sync, nonblock) the
      // substrate accepts and notes,
      // its files being memory already.
      o.append = (flags & 1) !== 0;
      return 0;
    },
    fd_prestat_get(fd, bufPtr) {
      if (fd !== 3) return ERR.BADF;
      const d = dv();
      d.setUint8(bufPtr + 0, 0);
      d.setUint32(bufPtr + 4, 1, true);
      return 0;
    },
    fd_prestat_dir_name(fd, pathPtr, len) {
      if (fd !== 3) return ERR.BADF;
      u8().set(enc.encode('/'), pathPtr);
      return 0;
    },
    fd_read(fd, iovsPtr, iovsLen, nreadPtr) {
      const o = fds.get(fd);
      if (!o) return ERR.BADF;
      let source = null;
      if (o.kind === 'stdin') source = stdindata;
      else if (o.kind === 'file') {
        const entry = files.get(o.path);
        if (!entry) return ERR.IO;
        if (entry.stagedEmpty) return ERR.IO;
        source = entry.data;
      } else return ERR.BADF;
      const d = dv();
      let read = 0;
      for (let i = 0; i < iovsLen; i++) {
        const ptr = d.getUint32(
          iovsPtr + i * 8, true);
        const len = d.getUint32(
          iovsPtr + i * 8 + 4, true);
        const avail = source.length - o.pos;
        const take = Math.min(len, Math.max(avail, 0));
        if (take > 0) {
          u8().set(source.subarray(
            o.pos, o.pos + take), ptr);
          o.pos += take;
          read += take;
        }
        if (take < len) break;
      }
      d.setUint32(nreadPtr, read, true);
      return 0;
    },
    fd_write(fd, iovsPtr, iovsLen, nwrittenPtr) {
      const o = fds.get(fd);
      if (!o) return ERR.BADF;
      const d = dv();
      let written = 0;
      const chunks = [];
      for (let i = 0; i < iovsLen; i++) {
        const ptr = d.getUint32(
          iovsPtr + i * 8, true);
        const len = d.getUint32(
          iovsPtr + i * 8 + 4, true);
        chunks.push(u8().subarray(ptr, ptr + len));
        written += len;
      }
      if (o.kind === 'stdout' ||
          o.kind === 'stderr') {
        let all = new Uint8Array(written);
        let at = 0;
        for (const c of chunks) {
          all.set(c, at); at += c.length;
        }
        const text = streamDecoders[fd].decode(
          all, { stream: true });
        if (text) {
          host.post({ t: 'out', fd, s: text });
        }
      } else if (o.kind === 'file') {
        const entry = files.get(o.path);
        if (!entry) return ERR.IO;
        if (o.append) o.pos = entry.data.length;
        for (const c of chunks) {
          const need = o.pos + c.length;
          if (need > entry.data.length) {
            const grown = new Uint8Array(need);
            grown.set(entry.data);
            entry.data = grown;
          }
          entry.data.set(c, o.pos);
          o.pos += c.length;
        }
        entry.mtime = Date.now();
        entry.stagedEmpty = false;
        o.dirty = true;
      } else return ERR.BADF;
      d.setUint32(nwrittenPtr, written, true);
      return 0;
    },
    fd_seek(fd, offset, whence, newposPtr) {
      const o = fds.get(fd);
      if (!o || o.kind !== 'file') {
        return ERR.BADF;
      }
      const entry = files.get(o.path);
      if (!entry) return ERR.IO;
      let base = 0;
      if (whence === 1) base = o.pos;
      if (whence === 2) base = entry.data.length;
      let np = base + Number(offset);
      if (np < 0) return ERR.INVAL;
      o.pos = np;
      dv().setBigUint64(newposPtr,
        BigInt(np), true);
      return 0;
    },
    fd_filestat_get(fd, bufPtr) {
      const o = fds.get(fd);
      if (!o) return ERR.BADF;
      if (o.kind === 'dir') {
        writeFilestat(bufPtr, o.path,
          files.get(o.path));
        return 0;
      }
      if (o.kind === 'file') {
        writeFilestat(bufPtr, o.path,
          files.get(o.path));
        return 0;
      }
      writeFilestat(bufPtr, '/dev',
        { dir: false,
          data: new Uint8Array(0),
          mtime: 0 });
      return 0;
    },
    fd_filestat_set_size(fd, size) {
      const o = fds.get(fd);
      if (!o || o.kind !== 'file') {
        return ERR.BADF;
      }
      const entry = files.get(o.path);
      if (!entry) return ERR.IO;
      const n = Number(size);
      const next = new Uint8Array(n);
      next.set(entry.data.subarray(
        0, Math.min(n, entry.data.length)));
      entry.data = next;
      entry.mtime = Date.now();
      entry.stagedEmpty = false;
      o.dirty = true;
      return 0;
    },
    fd_datasync(fd) {
      const o = fds.get(fd);
      if (o) flushFile(o);
      return 0;
    },
    fd_sync(fd) {
      const o = fds.get(fd);
      if (o) flushFile(o);
      return 0;
    },
    fd_readdir(fd, bufPtr, bufLen, cookie,
               bufusedPtr) {
      const o = fds.get(fd);
      if (!o || o.kind !== 'dir') {
        return ERR.BADF;
      }
      const names = childrenOf(o.path);
      const d = dv();
      let at = bufPtr;
      const end = bufPtr + bufLen;
      let idx = Number(cookie);
      let wroteAny = false;
      while (idx < names.length) {
        const name = names[idx];
        const nb = enc.encode(name);
        const need = 24 + nb.length;
        if (at + need > end) {
          if (!wroteAny) {
            // One entry must fit whole
            // or the caller can never
            // advance; report the space
            // used by a truncated header.
            if (end - at >= 24) {
              d.setBigUint64(at,
                BigInt(idx + 1), true);
              d.setBigUint64(at + 8,
                BigInt(inodeOf(
                  normalize(name, o.path))), true);
              d.setUint32(at + 16,
                nb.length, true);
              const childPath = normalize(
                name, o.path);
              d.setUint8(at + 20,
                files.get(childPath).dir
                  ? FT.DIR : FT.FILE);
              const fit = Math.min(
                nb.length, end - at - 24);
              u8().set(nb.subarray(0, fit),
                at + 24);
              at = end;
            }
          }
          break;
        }
        const childPath = normalize(name, o.path);
        d.setBigUint64(at, BigInt(idx + 1), true);
        d.setBigUint64(at + 8,
          BigInt(inodeOf(childPath)), true);
        d.setUint32(at + 16, nb.length, true);
        d.setUint8(at + 20,
          files.get(childPath).dir
            ? FT.DIR : FT.FILE);
        u8().set(nb, at + 24);
        at += need;
        idx += 1;
        wroteAny = true;
      }
      d.setUint32(bufusedPtr, at - bufPtr, true);
      return 0;
    },

    path_open(dirfd, dirflags, pathPtr,
              pathLen, oflags, rightsBase,
              rightsInh, fdflags, fdPtr) {
      const raw = readStr(pathPtr, pathLen);
      const full = resolveDirFd(dirfd, raw);
      if (full === null) return ERR.BADF;
      if (full.length > 512) {
        return ERR.NAMETOOLONG;
      }
      // oflags is a u16 in preview1 —
      // plain number math.
      const creat = (oflags & 1) !== 0;
      const wantDir = (oflags & 2) !== 0;
      const excl = (oflags & 4) !== 0;
      const trunc = (oflags & 8) !== 0;
      let entry = files.get(full);
      if (!entry) {
        if (!creat) return ERR.NOENT;
        const parent = files.get(parentOf(full));
        if (!parent || !parent.dir) {
          return ERR.NOTDIR;
        }
        entry = {
          dir: false,
          data: new Uint8Array(0),
          mtime: Date.now(),
        };
        files.set(full, entry);
        host.post({
          t: 'write', path: full, b64: '',
        });
      } else {
        if (creat && excl) return ERR.EXIST;
        if (wantDir && !entry.dir) {
          return ERR.NOTDIR;
        }
        if (entry.dir && !wantDir) {
          // Opening a directory without
          // the directory flag: hand back
          // a dir fd only if no write was
          // asked; reads of a directory
          // still fail honestly.
          const wantsWrite =
            (rightsBase & (1n << 6n)) !== 0n;
          if (wantsWrite) return ERR.ISDIR;
        }
      }
      const fd = nextFd++;
      if (entry.dir) {
        fds.set(fd, { kind: 'dir', path: full });
      } else {
        if (trunc) {
          entry.data = new Uint8Array(0);
          entry.mtime = Date.now();
          host.post({
            t: 'write', path: full, b64: '',
          });
        }
        fds.set(fd, {
          kind: 'file', path: full, pos: 0,
          append: (fdflags & 1) !== 0,
          dirty: false,
        });
      }
      dv().setUint32(fdPtr, fd, true);
      return 0;
    },
    path_filestat_get(dirfd, flags, pathPtr,
                      pathLen, bufPtr) {
      const full = resolveDirFd(
        dirfd, readStr(pathPtr, pathLen));
      if (full === null) return ERR.BADF;
      const entry = files.get(full);
      if (!entry) return ERR.NOENT;
      writeFilestat(bufPtr, full, entry);
      return 0;
    },
    path_create_directory(dirfd, pathPtr,
                          pathLen) {
      const full = resolveDirFd(
        dirfd, readStr(pathPtr, pathLen));
      if (full === null) return ERR.BADF;
      if (files.has(full)) return ERR.EXIST;
      const parent = files.get(parentOf(full));
      if (!parent || !parent.dir) {
        return ERR.NOTDIR;
      }
      files.set(full, {
        dir: true, data: new Uint8Array(0),
        mtime: Date.now(),
      });
      host.post({ t: 'mkdir', path: full });
      return 0;
    },
    path_unlink_file(dirfd, pathPtr, pathLen) {
      const full = resolveDirFd(
        dirfd, readStr(pathPtr, pathLen));
      if (full === null) return ERR.BADF;
      const entry = files.get(full);
      if (!entry) return ERR.NOENT;
      if (entry.dir) return ERR.ISDIR;
      files.delete(full);
      host.post({ t: 'unlink', path: full });
      return 0;
    },
    path_remove_directory(dirfd, pathPtr,
                          pathLen) {
      const full = resolveDirFd(
        dirfd, readStr(pathPtr, pathLen));
      if (full === null) return ERR.BADF;
      const entry = files.get(full);
      if (!entry) return ERR.NOENT;
      if (!entry.dir) return ERR.NOTDIR;
      if (childrenOf(full).length > 0) {
        return ERR.NOTEMPTY;
      }
      files.delete(full);
      host.post({ t: 'rmdir', path: full });
      return 0;
    },
    path_rename(oldDirfd, oldPtr, oldLen,
                newDirfd, newPtr, newLen) {
      const from = resolveDirFd(
        oldDirfd, readStr(oldPtr, oldLen));
      const to = resolveDirFd(
        newDirfd, readStr(newPtr, newLen));
      if (from === null || to === null) {
        return ERR.BADF;
      }
      const entry = files.get(from);
      if (!entry) return ERR.NOENT;
      const parent = files.get(parentOf(to));
      if (!parent || !parent.dir) {
        return ERR.NOTDIR;
      }
      // Move the entry and, for a
      // directory, its whole subtree.
      const moves = [];
      for (const key of files.keys()) {
        if (key === from ||
            key.startsWith(from + '/')) {
          moves.push(key);
        }
      }
      for (const key of moves) {
        const e = files.get(key);
        files.delete(key);
        files.set(to + key.slice(from.length), e);
      }
      host.post({ t: 'rename', from, to });
      return 0;
    },
    path_filestat_set_times(dirfd, flags,
                            pathPtr, pathLen,
                            atim, mtim, fstFlags) {
      const full = resolveDirFd(
        dirfd, readStr(pathPtr, pathLen));
      if (full === null) return ERR.BADF;
      const entry = files.get(full);
      if (!entry) return ERR.NOENT;
      if ((fstFlags & 4) !== 0) {
        entry.mtime = Number(mtim / 1000000n);
      } else if ((fstFlags & 8) !== 0) {
        entry.mtime = Date.now();
      }
      return 0;
    },
    path_link() { return ERR.NOSYS; },
    path_symlink() { return ERR.NOSYS; },
    path_readlink() { return ERR.NOSYS; },

    clock_time_get(id, precision, resultPtr) {
      let ns;
      if (id === 0) {
        ns = BigInt(Date.now()) * 1000000n;
      } else {
        ns = BigInt(Math.floor(
          performance.now() * 1000000));
      }
      dv().setBigUint64(resultPtr, ns, true);
      return 0;
    },
    random_get(bufPtr, len) {
      const bytes = new Uint8Array(len);
      const CH = 65536;
      for (let i = 0; i < len; i += CH) {
        crypto.getRandomValues(
          bytes.subarray(i, i + CH));
      }
      u8().set(bytes, bufPtr);
      return 0;
    },
    sched_yield() { return 0; },
    poll_oneoff(inPtr, outPtr, nsubs,
                neventsPtr) {
      const d = dv();
      let wakeAt = null;
      const events = [];
      for (let i = 0; i < nsubs; i++) {
        const base = inPtr + i * 48;
        const userdata = d.getBigUint64(
          base, true);
        const type = d.getUint8(base + 8);
        if (type === 0) {
          const timeout = d.getBigUint64(
            base + 24, true);
          const flags = d.getUint16(
            base + 40, true);
          const now = BigInt(Math.floor(
            performance.now() * 1000000));
          const deadline = (flags & 1) !== 0
            ? timeout
            : now + timeout;
          if (wakeAt === null ||
              deadline < wakeAt) {
            wakeAt = deadline;
          }
          events.push({ userdata, type });
        } else {
          events.push({
            userdata, type, error: ERR.INVAL,
          });
        }
      }
      if (wakeAt !== null) {
        const target = Number(wakeAt) / 1000000;
        // The page is the guest's whole
        // world; waiting here IS the
        // scheduler's sleep. The kernel's
        // wall quota bounds it.
        while (performance.now() < target) {
          // wait
        }
      }
      let count = 0;
      for (const ev of events) {
        if (ev.type !== 0 && !ev.error) continue;
        const base = outPtr + count * 32;
        d.setBigUint64(base, ev.userdata, true);
        d.setUint16(base + 8, ev.error || 0, true);
        d.setUint8(base + 10, ev.type);
        count++;
      }
      d.setUint32(neventsPtr, count, true);
      return 0;
    },
    proc_exit(code) {
      host.post({ t: 'exit', code });
      throw new WasiExit(code);
    },
    proc_raise() { return ERR.NOSYS; },
  };

  return {
    imports: { wasi_snapshot_preview1: wasi },
    bind(instance) {
      memory = instance.exports.memory;
    },
  };
}

async function startGuest(config, bytes, host) {
  const { imports, bind } = makeWasi(config, host);
  const { instance } = await WebAssembly
    .instantiate(bytes, imports);
  bind(instance);
  let code = 0;
  try {
    instance.exports._start();
  } catch (e) {
    if (e instanceof WasiExit) {
      code = e.code;
    } else {
      host.post({
        t: 'out', fd: 2,
        s: 'the guest trapped: ' +
          (e && e.message ? e.message : e) + '\n',
      });
      code = 1;
    }
  }
  return code;
}

if (typeof module !== 'undefined') {
  module.exports = { makeWasi, startGuest, WasiExit };
}
