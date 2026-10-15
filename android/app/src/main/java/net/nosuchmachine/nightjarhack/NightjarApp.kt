package net.nosuchmachine.nightjarhack

import android.app.Application
import kotlinx.coroutines.flow.MutableStateFlow

/// The app shell: one of each engine, wired the way the iOS
/// app wires its environment objects.
class NightjarApp : Application() {
    lateinit var post: ListeningPost
    lateinit var book: PayloadBook
    lateinit var mouth: Mouth
    lateinit var serve: Serve
    lateinit var crawl: CrawlEngine
    lateinit var ble: BleMouth
    lateinit var engines: Engines
    lateinit var scanner: PortScanner

    /// Scan → Send handoff (a target, and optionally the name
    /// of the library probe that speaks its port's language).
    val sendHandoff = MutableStateFlow<String?>(null)
    val sendHandoffPayload = MutableStateFlow<String?>(null)

    override fun onCreate() {
        super.onCreate()
        post = ListeningPost(this)
        book = PayloadBook(this)
        mouth = Mouth(this)
        serve = Serve(this, mouth)
        crawl = CrawlEngine(mouth, serve)
        ble = BleMouth(this, mouth)
        engines = Engines(mouth)
        scanner = PortScanner()
        mouth.bleArrivalHandler = { from, data ->
            serve.injectBleArrival(from, data)
        }
        // Coil with GIF support for the centipede splash.
        coil.Coil.setImageLoader(
            coil.ImageLoader.Builder(this)
                .components {
                    add(coil.decode.GifDecoder.Factory())
                }
                .build()
        )
    }
}
