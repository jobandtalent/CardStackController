![](https://github.com/jobandtalent/AnimatedTextInput/blob/master/Assets/Jobandtalent%20Eng.png)

# CardStackController
iOS custom controller used in the [Jobandtalent app](https://itunes.apple.com/app/id665060895) to present new view controllers as cards.

This controller behaves very similar to `UINavigationController`, maintaining a stack of ViewControllers. The presentation of new view controllers is different though. New view controllers are presented as a new “Card” in front of the current context. The next GIFs show the control in action.

Gif from the example project supplied:

![](https://github.com/jobandtalent/CardStackController/blob/master/Assets/cards.gif?raw=true)


Gif from the Jobandtalent app:

![](https://github.com/jobandtalent/CardStackController/blob/master/Assets/cards-app.gif?raw=true)


## Installation
Use Cocoapods to install this custom control in your project.

```
pod ‘CardStackController’, '~> 0.1.0’
```

## Usage
Use the main and only public class `CardStackController` to present or stack new view controllers.
After creating and configuring `CardStackController`, present it modally (it doesn’t need to be animated). Once the controller itself is presented, you can start stacking cards by calling `stack(viewController:)` method.

Example of usage:

```swift
cardStackController.delegate = self
cardStackController.cardScaleFactor = CGFloat(firstSlider.value)
cardStackController.firstCardTopOffset = CGFloat(secondSlider.value)
cardStackController.topOffsetBetweenCards = CGFloat(thirdSlider.value)
cardStackController.verticalTranslation = CGFloat(fourthSlider.value)
cardStackController.automaticallyDismiss = false
present(cardStackController, animated: false, completion: nil)

let root = newController()
root.delegate = self
cardStackController.stack(viewController: root)
```


This control is highly customisable and contains many features, among the ones we highlight:
- The user can dismiss cards by dragging them down.
- It is possible to tune the `damping` and `frequency` values of the presenting animation to achieve all kinds of animation curves.
- It is possible to customise the top distance between cards, the amount each card gets resized, the size of each card… 
- There are many convenient methods to unstack cards: `unstackAll`, `unstackUntilRoot`, `unstackLast`, etc.


## Under the hood
`CardStackController` uses `UIKit Dynamics` to present or stack cards. It creates an attachment behaviour between a card and a fix point on the screen. To prevent the card moving sideways, there is a collision behaviour between each card and the borders of the screen. Finally, there is a DynamicItem behaviour for each card to prevent rotation (this behaviour could also be used to apply density/friction/etc to them, but we didn’t find it necessary).



CardStackController is available under the MIT license. See the LICENSE file for more info.
