Gradle's prepareSharedArtwork task automatically includes the existing
iOS artwork in the Android build. No manual copies are needed:

  background.jpg  <- ios/nightjar/Assets.xcassets/AppBackground.imageset/background.jpg
  centipede.gif   <- ios/nightjar/centipede.gif

The launcher icon is likewise the iOS app's icon:

  generated res/mipmap-xxxhdpi/ic_launcher.png
      <- ios/nightjar/Assets.xcassets/AppIcon.appiconset/IMG_1434.png
