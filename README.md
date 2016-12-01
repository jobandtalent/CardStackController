# CardStackController

[![CI Status](http://img.shields.io/travis/Victor Baro/CardStackController.svg?style=flat)](https://travis-ci.org/Victor Baro/CardStackController)
[![Version](https://img.shields.io/cocoapods/v/CardStackController.svg?style=flat)](http://cocoapods.org/pods/CardStackController)
[![License](https://img.shields.io/cocoapods/l/CardStackController.svg?style=flat)](http://cocoapods.org/pods/CardStackController)
[![Platform](https://img.shields.io/cocoapods/p/CardStackController.svg?style=flat)](http://cocoapods.org/pods/CardStackController)


![](https://github.com/jobandtalent/AnimatedTextInput/blob/master/Assets/Jobandtalent%20Eng.png)

iOS custom view controllercomponent used in [Jobandtalent app](https://itunes.apple.com/app/id665060895).
CardStackController allows you to present any number of ViewControllers, one on top of another, using a card stack arrengement. The controller uses a very simple API (based on `UINavigationController`).

![](https://github.com/jobandtalent/AnimatedTextInput/blob/master/Assets/general.gif)

## Installation
Use cocoapods to install this custom control in your project.

```
pod 'CardStackController', '~> 0.0.1'
```

Full `Swift 3.0` support -> Thanks to @poolqf

## Usage

Use the main (and only) class `CardStackController`. The API was designed to be very similar to a UINavigationController.

The best way to initialize this control is by using `init(rootViewController:)`. If you initialize it without a root view controller, the first ViewController you stack will become the rootViewController.

```swift
//Option 1
cardStackController = CardStackController(rootViewController: rootController)
// No need to call stack(viewController:), will be presented automatically
presentViewController(cardStackController, animated: false, completion: nil)


//Option 2
cardStackController = CardStackController()
//Additional setup
presentViewController(cardStackController, animated: false, completion: nil)
//Calling stack(viewController:) is necessary
cardStackController.stack(viewController: rootController)

```


To present a new card, just call `stack()`

Example:


## License

CardStackController is available under the MIT license. See the LICENSE file for more info.
