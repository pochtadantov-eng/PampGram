import Foundation
import UIKit
import MapKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

/// A deliberately small local map picker used by PampGram's fake-location setting. The pin
/// stays fixed in the centre while the user pans the map. Nothing is sent when this screen is
/// open: only tapping "Применить" writes the centre coordinate to PampGram settings.
final class PampGramLocationMapController: ViewController {
    private let presentationData: PresentationData
    private let initialCoordinate: CLLocationCoordinate2D
    private let applyCoordinate: (CLLocationCoordinate2D) -> Void
    private let mapView = MKMapView(frame: .zero)

    init(presentationData: PresentationData, initialCoordinate: CLLocationCoordinate2D, applyCoordinate: @escaping (CLLocationCoordinate2D) -> Void) {
        self.presentationData = presentationData
        self.initialCoordinate = initialCoordinate
        self.applyCoordinate = applyCoordinate
        super.init(navigationBarPresentationData: nil)
        self.title = "Выбрать на карте"
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Назад", style: .plain, target: self, action: #selector(self.backPressed))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Применить", style: .done, target: self, action: #selector(self.applyPressed))
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadDisplayNode() {
        self.mapView.showsUserLocation = false
        self.mapView.isRotateEnabled = true
        self.mapView.isPitchEnabled = false
        if abs(self.initialCoordinate.latitude) > 0.000001 || abs(self.initialCoordinate.longitude) > 0.000001 {
            self.mapView.setRegion(MKCoordinateRegion(center: self.initialCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)), animated: false)
        } else {
            self.mapView.setVisibleMapRect(MKMapRect.world, edgePadding: UIEdgeInsets(top: 80, left: 24, bottom: 80, right: 24), animated: false)
        }
        let node = ASDisplayNode(viewBlock: { [mapView = self.mapView] in mapView })
        self.displayNode = node
        self.displayNodeDidLoad()

        let pin = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
        pin.tintColor = self.presentationData.theme.list.itemAccentColor
        pin.contentMode = .scaleAspectFit
        pin.translatesAutoresizingMaskIntoConstraints = false
        node.view.addSubview(pin)
        NSLayoutConstraint.activate([
            pin.centerXAnchor.constraint(equalTo: node.view.centerXAnchor),
            pin.centerYAnchor.constraint(equalTo: node.view.centerYAnchor, constant: -14.0),
            pin.widthAnchor.constraint(equalToConstant: 38.0),
            pin.heightAnchor.constraint(equalToConstant: 38.0)
        ])
        let dot = UIView()
        dot.backgroundColor = self.presentationData.theme.list.itemAccentColor
        dot.layer.cornerRadius = 3.0
        dot.translatesAutoresizingMaskIntoConstraints = false
        node.view.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.centerXAnchor.constraint(equalTo: node.view.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: node.view.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6.0),
            dot.heightAnchor.constraint(equalToConstant: 6.0)
        ])
    }

    @objc private func backPressed() {
        if let navigationController = self.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            self.dismiss()
        }
    }

    @objc private func applyPressed() {
        self.applyCoordinate(self.mapView.centerCoordinate)
        self.backPressed()
    }
}
