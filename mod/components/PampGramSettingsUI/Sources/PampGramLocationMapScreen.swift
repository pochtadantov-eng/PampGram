import Foundation
import UIKit
import MapKit

/// Lightweight local picker used by PampGram fake-location settings. It never requests the
/// device's current position: the map opens on the previously saved coordinate, the pin stays
/// fixed in the center, and only the map underneath moves.
final class PampGramLocationMapViewController: UIViewController {
    private let mapView = MKMapView(frame: .zero)
    private let initialCoordinate: CLLocationCoordinate2D
    private let applyCoordinate: (CLLocationCoordinate2D) -> Void

    init(latitude: Double, longitude: Double, apply: @escaping (CLLocationCoordinate2D) -> Void) {
        self.initialCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.applyCoordinate = apply
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        self.mapView.translatesAutoresizingMaskIntoConstraints = false
        self.mapView.showsUserLocation = false
        self.mapView.isRotateEnabled = true
        self.mapView.isPitchEnabled = false
        self.view.addSubview(self.mapView)
        NSLayoutConstraint.activate([
            self.mapView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.mapView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.mapView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.mapView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        self.mapView.setRegion(MKCoordinateRegion(center: self.initialCoordinate, latitudinalMeters: 2500.0, longitudinalMeters: 2500.0), animated: false)

        let topMaterial = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        topMaterial.translatesAutoresizingMaskIntoConstraints = false
        topMaterial.layer.cornerRadius = 18.0
        topMaterial.clipsToBounds = true
        self.view.addSubview(topMaterial)

        let back = UIButton(type: .system)
        back.translatesAutoresizingMaskIntoConstraints = false
        back.setTitle("‹ Назад", for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 17.0, weight: .semibold)
        back.addTarget(self, action: #selector(self.backPressed), for: .touchUpInside)
        topMaterial.contentView.addSubview(back)

        let apply = UIButton(type: .system)
        apply.translatesAutoresizingMaskIntoConstraints = false
        apply.setTitle("Применить", for: .normal)
        apply.titleLabel?.font = .systemFont(ofSize: 17.0, weight: .semibold)
        apply.addTarget(self, action: #selector(self.applyPressed), for: .touchUpInside)
        topMaterial.contentView.addSubview(apply)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Выбрать точку"
        title.font = .systemFont(ofSize: 17.0, weight: .bold)
        title.textAlignment = .center
        topMaterial.contentView.addSubview(title)

        NSLayoutConstraint.activate([
            topMaterial.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 10.0),
            topMaterial.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10.0),
            topMaterial.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 6.0),
            topMaterial.heightAnchor.constraint(equalToConstant: 52.0),
            back.leadingAnchor.constraint(equalTo: topMaterial.contentView.leadingAnchor, constant: 10.0),
            back.centerYAnchor.constraint(equalTo: topMaterial.contentView.centerYAnchor),
            back.widthAnchor.constraint(greaterThanOrEqualToConstant: 76.0),
            back.heightAnchor.constraint(equalToConstant: 44.0),
            apply.trailingAnchor.constraint(equalTo: topMaterial.contentView.trailingAnchor, constant: -10.0),
            apply.centerYAnchor.constraint(equalTo: topMaterial.contentView.centerYAnchor),
            apply.widthAnchor.constraint(greaterThanOrEqualToConstant: 88.0),
            apply.heightAnchor.constraint(equalToConstant: 44.0),
            title.centerXAnchor.constraint(equalTo: topMaterial.contentView.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: topMaterial.contentView.centerYAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: back.trailingAnchor, constant: 4.0),
            title.trailingAnchor.constraint(lessThanOrEqualTo: apply.leadingAnchor, constant: -4.0)
        ])

        let pin = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
        pin.translatesAutoresizingMaskIntoConstraints = false
        pin.tintColor = .systemRed
        pin.contentMode = .scaleAspectFit
        self.view.addSubview(pin)
        NSLayoutConstraint.activate([
            pin.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            pin.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: -16.0),
            pin.widthAnchor.constraint(equalToConstant: 42.0),
            pin.heightAnchor.constraint(equalToConstant: 42.0)
        ])

        let hint = UILabel()
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.text = "Двигай карту под меткой"
        hint.font = .systemFont(ofSize: 13.0, weight: .medium)
        hint.textAlignment = .center
        hint.textColor = .label
        hint.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.92)
        hint.layer.cornerRadius = 14.0
        hint.clipsToBounds = true
        self.view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -12.0),
            hint.heightAnchor.constraint(equalToConstant: 34.0),
            hint.widthAnchor.constraint(greaterThanOrEqualToConstant: 190.0)
        ])
    }

    @objc private func backPressed() { self.dismiss(animated: true) }
    @objc private func applyPressed() {
        self.applyCoordinate(self.mapView.centerCoordinate)
        self.dismiss(animated: true)
    }
}
