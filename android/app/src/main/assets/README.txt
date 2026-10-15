The two assets the app loads at runtime are binary files, and
they already live in this repository under ios/ — copy them
here before building (they are byte-identical to the iOS
app's copies):

  background.jpg  <- ios/nightjar/Assets.xcassets/AppBackground.imageset/background.jpg
  centipede.gif   <- ios/nightjar/centipede.gif

The launcher icon is likewise the iOS app's icon:

  app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
      <- ios/nightjar/Assets.xcassets/AppIcon.appiconset/IMG_1434.png
