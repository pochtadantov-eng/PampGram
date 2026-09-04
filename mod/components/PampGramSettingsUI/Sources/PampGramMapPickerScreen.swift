import Foundation
import UIKit
import MapKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext

/// A minimal Apple-Maps (MapKit) coordinate picker: pan/zoom the map, the fixed center pin
/// marks the chosen point, "Готово" saves it. Used by "Фейковая геолокация" to set the faked
/// coordinate by tapping the map instead of typing latitude/longitude. Purely local — it never
/// reads or sends the device's real position (user location is not even shown).
public func pampGramMapPickerController(context: AccountContext, initialLatitude: Double, initialLongitude: Double, apply: @escaping (Double, Double) -> Void) -> ViewController {
    return PampGramMapPickerControllerImpl(context: context, initialLatitude: initialLatitude, initialLongitude: initialLongitude, apply: apply)
}

private final class PampGramMapPickerControllerImpl: ViewController {
    private let context: AccountContext
    private let initialLatitude: Double
    private let initialLongitude: Double
    private let applyCoordinate: (Double, Double) -> Void
    private let presentationData: PresentationData

    private var mapView: MKMapView?
    private var pinView: UIImageView?

    init(context: AccountContext, initialLatitude: Double, initialLongitude: Double, apply: @escaping (Double, Double) -> Void) {
        self.context = context
        self.initialLatitude = initialLatitude
        self.initialLongitude = initialLongitude
        self.applyCoordinate = apply
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }

        let navigationBarPresentationData = NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: self.presentationData.theme), strings: NavigationBarStrings(presentationStrings: self.presentationData.strings))
        super.init(navigationBarPresentationData: navigationBarPresentationData)

        self.title = "Выбор на карте"
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.donePressed))
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Cancel, style: .plain, target: self, action: #selector(self.cancelPressed))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ViewControllerTracingNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.plainBackgroundColor

        let mapView = MKMapView()
        mapView.showsUserLocation = false
        mapView.mapType = .standard
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: self.initialLatitude, longitude: self.initialLongitude), latitudinalMeters: 4000, longitudinalMeters: 4000)
        mapView.setRegion(region, animated: false)
        self.displayNode.view.addSubview(mapView)
        self.mapView = mapView

        let pinImage = generateTintedImage(image: UIImage(systemName: "mappin"), color: self.presentationData.theme.list.itemAccentColor) ?? UIImage(systemName: "mappin")
        let pinView = UIImageView(image: pinImage)
        pinView.contentMode = .scaleAspectFit
        self.displayNode.view.addSubview(pinView)
        self.pinView = pinView

        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        if let mapView = self.mapView {
            mapView.frame = CGRect(origin: CGPoint(), size: layout.size)
        }
        if let pinView = self.pinView {
            let pinSize = CGSize(width: 36.0, height: 44.0)
            // Bottom tip of the pin sits on the map center.
            pinView.frame = CGRect(x: (layout.size.width - pinSize.width) / 2.0, y: layout.size.height / 2.0 - pinSize.height, width: pinSize.width, height: pinSize.height)
        }
    }

    @objc private func donePressed() {
        if let coordinate = self.mapView?.centerCoordinate {
            self.applyCoordinate(coordinate.latitude, coordinate.longitude)
        }
        if let navigationController = self.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            self.dismiss()
        }
    }

    @objc private func cancelPressed() {
        if let navigationController = self.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        } else {
            self.dismiss()
        }
    }
}
