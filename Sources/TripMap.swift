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
    var night: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        // 底图：苹果地图（国内底图数据也是高德，坐标需为 GCJ-02）
        map.overrideUserInterfaceStyle = night ? .dark : .light
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let co = context.coordinator
        map.overrideUserInterfaceStyle = night ? .dark : .light
        co.night = night
        if co.builtCount != points.count || co.nightDrawn != night {
            co.rebuild(map, points: points)
        }
        co.moveCar(to: cursor, in: map, points: points)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var builtCount = -1
        var night = false
        var nightDrawn = false
        private let car = CarAnnotation(CLLocationCoordinate2D(latitude: 0, longitude: 0))
        private var carAdded = false

        func rebuild(_ map: MKMapView, points: [TrackPoint]) {
            builtCount = points.count
            nightDrawn = night
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
            map.addOverlays(segs.map { $0.0 }, level: .aboveLabels)

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


/// WGS-84 → GCJ-02（高德瓦片要用 GCJ，直接喂 WGS 会偏约 586 米）
func wgs2gcj(_ lat: Double, _ lon: Double) -> (Double, Double) {
    let a = 6378245.0, ee = 0.00669342162296594323
    func tLat(_ x: Double, _ y: Double) -> Double {
        var r = -100.0 + 2.0*x + 3.0*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
        r += (20.0*sin(6.0*x*Double.pi) + 20.0*sin(2.0*x*Double.pi)) * 2.0/3.0
        r += (20.0*sin(y*Double.pi) + 40.0*sin(y/3.0*Double.pi)) * 2.0/3.0
        r += (160.0*sin(y/12.0*Double.pi) + 320*sin(y*Double.pi/30.0)) * 2.0/3.0
        return r
    }
    func tLon(_ x: Double, _ y: Double) -> Double {
        var r = 300.0 + x + 2.0*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
        r += (20.0*sin(6.0*x*Double.pi) + 20.0*sin(2.0*x*Double.pi)) * 2.0/3.0
        r += (20.0*sin(x*Double.pi) + 40.0*sin(x/3.0*Double.pi)) * 2.0/3.0
        r += (150.0*sin(x/12.0*Double.pi) + 300.0*sin(x/30.0*Double.pi)) * 2.0/3.0
        return r
    }
    if lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271 { return (lat, lon) }
    var dLat = tLat(lon - 105.0, lat - 35.0)
    var dLon = tLon(lon - 105.0, lat - 35.0)
    let radLat = lat / 180.0 * Double.pi
    var magic = sin(radLat); magic = 1 - ee*magic*magic
    let sqrtMagic = sqrt(magic)
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Double.pi)
    dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * Double.pi)
    return (lat + dLat, lon + dLon)
}

/// 车辆当前位置小地图：高德瓦片 + 单点气泡（与网页端同一套底图和坐标）
struct LocationMapView: UIViewRepresentable {
    let lat: Double      // 已是 GCJ
    let lon: Double
    var span: Double = 0.006
    var night: Bool = false

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.overrideUserInterfaceStyle = night ? .dark : .light
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.overrideUserInterfaceStyle = night ? .dark : .light
        map.removeAnnotations(map.annotations)
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let pin = MKPointAnnotation()
        pin.coordinate = c
        map.addAnnotation(pin)
        var region = MKCoordinateRegion(center: c,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
        region = map.regionThatFits(region)
        map.setRegion(region, animated: false)
    }

    func makeCoordinator() -> LocCoord { LocCoord() }

    final class LocCoord: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let t = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: t) }
            return MKOverlayRenderer(overlay: overlay)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let id = "locpin"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            v.markerTintColor = .systemBlue
            v.glyphImage = UIImage(systemName: "car.fill")
            return v
        }
    }
}


/// 高德瓦片：夜间模式时把瓦片压成深色（高德没有公开的深色栅格样式，只能本地处理）
final class ThemeTileOverlay: MKTileOverlay {
    var night: Bool = false
    private let cache = NSCache<NSString, NSData>()

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let key = "n\(night ? 1 : 0)_\(path.z)_\(path.x)_\(path.y)" as NSString
        if let hit = cache.object(forKey: key) { result(hit as Data, nil); return }
        super.loadTile(at: path) { data, err in
            guard self.night, let data, let img = UIImage(data: data),
                  let dark = ThemeTileOverlay.darken(img), let png = dark.pngData() else {
                result(data, err); return
            }
            self.cache.setObject(png as NSData, forKey: key)
            result(png, nil)
        }
    }

    static func darken(_ img: UIImage) -> UIImage? {
        guard let ci = CIImage(image: img) else { return img }
        let ctx = CIContext(options: nil)
        // 经典的夜间地图做法：反相 + 色相转 180°，保持道路/水系的色彩关系
        guard let inv = CIFilter(name: "CIColorInvert", parameters: [kCIInputImageKey: ci]),
              let invOut = inv.outputImage,
              let hue = CIFilter(name: "CIHueAdjust", parameters: [kCIInputImageKey: invOut,
                                                                  kCIInputAngleKey: Double.pi]),
              let hueOut = hue.outputImage,
              let ctl = CIFilter(name: "CIColorControls", parameters: [
                  kCIInputImageKey: hueOut,
                  kCIInputSaturationKey: 0.55,
                  kCIInputBrightnessKey: -0.05,
                  kCIInputContrastKey: 0.88]),
              let out = ctl.outputImage,
              let cg = ctx.createCGImage(out, from: ci.extent) else { return img }
        return UIImage(cgImage: cg)
    }

}
