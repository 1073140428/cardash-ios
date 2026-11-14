import SwiftUI
import UIKit
import MapKit

/// 轨迹上的一个点（WGS-84，直接喂 MapKit）
struct TrackPoint: Identifiable, Equatable {
    let id = UUID()
    let ts: Double
    let lat: Double
    let lon: Double
    let speed: Double
    let rpm: Double
    let coolant: Double
    var brk: Bool = false      // 与前一点之间有 GPS 断档：不画连线

    var coord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// 按速度着色
func trackColor(_ v: Double) -> UIColor {
    switch v {
    case ..<10:  return UIColor(hex: 0x5B8DEF)
    case ..<30:  return UIColor(hex: 0x34C759)
    case ..<60:  return UIColor(hex: 0xFFCC00)
    case ..<90:  return UIColor(hex: 0xFF9500)
    default:     return UIColor(hex: 0xFF3B30)
    }
}

final class ColoredPolyline: MKPolyline {
    var color: UIColor = .blue
}

final class CarAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    init(_ c: CLLocationCoordinate2D) { coordinate = c }
}

/// MapKit 轨迹视图（UIViewRepresentable，兼容 iOS 16+）
struct TripMapView: UIViewRepresentable {
    let points: [TrackPoint]
    let cursor: Int

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        // 底图：高德瓦片（与服务端网页同一个源，坐标系 GCJ-02）
        let tpl = "https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}"
        let tile = MKTileOverlay(urlTemplate: tpl.replacingOccurrences(of: "{s}", with: "1"))
        tile.canReplaceMapContent = true
        tile.maximumZ = 18
        map.addOverlay(tile, level: .aboveLabels)
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let co = context.coordinator
        if co.builtCount != points.count {
            co.rebuild(map, points: points)
        }
        co.moveCar(to: cursor, in: map, points: points)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var builtCount = -1
        private let car = CarAnnotation(CLLocationCoordinate2D(latitude: 0, longitude: 0))
        private var carAdded = false

        func rebuild(_ map: MKMapView, points: [TrackPoint]) {
            builtCount = points.count
            for ov in map.overlays where ov is ColoredPolyline { map.removeOverlay(ov) }
            map.removeAnnotations(map.annotations)
            carAdded = false

            guard points.count > 1 else { return }

            // 分段着色
            var segs: [(MKPolyline, UIColor)] = []
            for i in 1..<points.count {
                let v = max(0, max(points[i-1].speed, points[i].speed))
                var coords = [points[i-1].coord, points[i].coord]
                let line = ColoredPolyline(coordinates: &coords, count: 2)
                line.color = trackColor(v)
                segs.append((line, line.color))
            }
            map.addOverlays(segs.map { $0.0 })

            // 起终点
            let start = MKPointAnnotation()
            start.coordinate = points[0].coord
            start.title = "起点"
            let end = MKPointAnnotation()
            end.coordinate = points[points.count-1].coord
            end.title = "终点"
            map.addAnnotations([start, end])

            // 停车点（<1km/h 且 ≥60 秒）
            var runStart: Int? = nil
            for i in 0..<points.count {
                let stopped = points[i].speed < 1
                if stopped && runStart == nil { runStart = i }
                if (!stopped || i == points.count - 1), let st = runStart {
                    let en = stopped ? i : i - 1
                    let dur = (points[en].ts - points[st].ts) / 1000
                    if dur >= 60 {
                        let a = MKPointAnnotation()
                        a.coordinate = points[(st + en) / 2].coord
                        a.title = "停车 \(Int(dur / 60)) 分钟"
                        map.addAnnotation(a)
                    }
                    runStart = nil
                }
            }

            map.addAnnotation(car)
            carAdded = true

            let lats = points.map { $0.lat }, lons = points.map { $0.lon }
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLon = lons.min()!, maxLon = lons.max()!
            let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.35, 0.004),
                                        longitudeDelta: max((maxLon - minLon) * 1.35, 0.004))
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                               longitude: (minLon + maxLon) / 2),
                span: span)
            map.setRegion(region, animated: false)
        }

        func moveCar(to index: Int, in map: MKMapView, points: [TrackPoint]) {
            guard !points.isEmpty, index >= 0, index < points.count else { return }
            car.coordinate = points[index].coord
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: t)
            }
            if let line = overlay as? ColoredPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = line.color
                r.lineWidth = 5
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation === car {
                let id = "car"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKAnnotationView
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                let size: CGFloat = 22
                let dot = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
                dot.backgroundColor = UIColor(hex: 0x2F6FB0)
                dot.layer.cornerRadius = size / 2
                dot.layer.borderWidth = 3
                dot.layer.borderColor = UIColor.white.cgColor
                dot.isUserInteractionEnabled = false
                v.subviews.forEach { $0.removeFromSuperview() }
                v.addSubview(dot)
                v.frame = CGRect(x: 0, y: 0, width: size, height: size)
                v.centerOffset = .zero
                v.canShowCallout = false
                return v
            }

            let id = "dot"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            v.markerTintColor = UIColor(hex: 0x8A97A8)
            v.glyphImage = UIImage(systemName: "pause.fill")
            v.displayPriority = .defaultLow
            v.canShowCallout = true
            return v
        }
    }
}

extension UIColor {
    convenience init(hex: Int) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
