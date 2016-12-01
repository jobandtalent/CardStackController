import UIKit
import CardStackController

protocol CardViewControllerDelegate: class {
    func dismiss()
    func stackAnotherCard()
    func dismissAllCards()
}

class CardViewController: UIViewController {

    weak var delegate: CardViewControllerDelegate!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.random()
    }

    @IBAction func tap(sender: AnyObject) {
        delegate.stackAnotherCard()
    }

    @IBAction func closeButtonPressed(_ sender: Any) {
        delegate.dismiss()
    }
    
    @IBAction func dismissAllPressed(_ sender: Any) {
        delegate.dismissAllCards()
    }
}

extension UIColor {
    static func random() -> UIColor {
        let randomNumber = arc4random() % 4
        switch randomNumber {
        case 0:
            return UIColor.blue
        case 1:
            return UIColor.orange
        case 2:
            return UIColor.green
        case 3:
            return UIColor.brown
        default:
            return UIColor.white
        }
    }
}
