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
            return UIColor(red: 230, green: 230, blue: 250)
        case 1:
            return UIColor(red: 255, green: 250, blue: 129)
        case 2:
            return UIColor(red: 133, green: 202, blue: 93)
        case 3:
            return UIColor(red: 253, green: 222, blue: 238)
        default:
            return UIColor.white
        }
    }

    convenience init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.init(red: red/255.0, green: green/255.0, blue: blue/255.0, alpha: 1.0)
    }
}
