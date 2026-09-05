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

        let pinView = UIImageView(image: PampGramMapPickerControllerImpl.pinImage(color: self.presentationData.theme.list.itemAccentColor, size: CGSize(width: 36.0, height: 60.0)))
        pinView.contentMode = .scaleAspectFit
        self.displayNode.view.addSubview(pinView)
        self.pinView = pinView

        self.displayNodeDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // "Отмена" is the only way out — kill the swipe-from-left-edge pop gesture, so the
        // fake-location target can't be accidentally discarded mid-drag on the map.
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    /// Custom "pin" for the fake-location picker — two balls on top, a shaft extending down
    /// to the map centre, and a slit at the tip. Rendered with `UIGraphicsImageRenderer` in
    /// the theme's accent colour; the bottom tip is the point that lands on the target
    /// coordinate (`containerLayoutUpdated` positions the image accordingly).
    private static func pinImage(color: UIColor, size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let width = size.width
            let height = size.height

            let ballRadius: CGFloat = width * 0.19
            let ballCenterY: CGFloat = ballRadius + 1.0
            let leftBallCenter = CGPoint(x: width * 0.5 - ballRadius * 0.9, y: ballCenterY)
            let rightBallCenter = CGPoint(x: width * 0.5 + ballRadius * 0.9, y: ballCenterY)

            let shaftWidth: CGFloat = width * 0.44
            let shaftTop: CGFloat = ballCenterY
            let shaftBottom: CGFloat = height - 1.0
            let shaftRect = CGRect(x: (width - shaftWidth) / 2.0, y: shaftTop, width: shaftWidth, height: shaftBottom - shaftTop)
            let shaftPath = UIBezierPath(roundedRect: shaftRect, cornerRadius: shaftWidth / 2.0)

            color.setFill()
            let leftBall = UIBezierPath(arcCenter: leftBallCenter, radius: ballRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            let rightBall = UIBezierPath(arcCenter: rightBallCenter, radius: ballRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            leftBall.fill()
            rightBall.fill()
            shaftPath.fill()

            // Slit at the tip.
            let slitWidth: CGFloat = width * 0.05
            let slitHeight: CGFloat = shaftWidth * 0.42
            let slitRect = CGRect(x: (width - slitWidth) / 2.0, y: shaftBottom - slitHeight - 2.0, width: slitWidth, height: slitHeight)
            let slitPath = UIBezierPath(roundedRect: slitRect, cornerRadius: slitWidth / 2.0)
            cg.setBlendMode(.destinationOut)
            slitPath.fill()
            cg.setBlendMode(.normal)
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        if let mapView = self.mapView {
            mapView.frame = CGRect(origin: CGPoint(), size: layout.size)
        }
        if let pinView = self.pinView {
            let pinSize = CGSize(width: 36.0, height: 60.0)
            // Bottom tip of the pin (slit) sits on the map center.
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
