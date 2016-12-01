import UIKit
import CardStackController

class ViewController: UIViewController {

    let cardStackController = CardStackController()
    @IBOutlet var firstSliderLabel: UILabel!
    @IBOutlet var secondSliderLabel: UILabel!
    @IBOutlet var thirdSliderLabel: UILabel!
    @IBOutlet var firstSlider: UISlider!
    @IBOutlet var secondSlider: UISlider!
    @IBOutlet var thirdSlider: UISlider!
    @IBOutlet var fourthSliderLabel: UILabel!
    @IBOutlet var fourthSlider: UISlider!

    @IBAction func tapPressed(sender: AnyObject) {
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
    }

    @IBAction func sliderValueChanged(sender: UISlider) {
        firstSliderLabel.text = "\(firstSlider.value)"
        secondSliderLabel.text = "\(Int(secondSlider.value))"
        thirdSliderLabel.text = "\(Int(thirdSlider.value))"
        fourthSliderLabel.text = "\(Int(fourthSlider.value))"
    }

    fileprivate func newController() -> CardViewController {
        return UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "CardViewController") as! CardViewController
    }
}

extension ViewController: CardViewControllerDelegate {
    func dismiss() {
        cardStackController.unstackLastViewController()
    }

    func stackAnotherCard() {
        let card = newController()
        card.delegate = self
        cardStackController.stack(viewController: card, completion: { print("Completion block") })
    }

    func dismissAllCards() {
        cardStackController.unstackAllViewControllers()
    }
}

extension ViewController: CardStackControllerDelegate {
    
}
