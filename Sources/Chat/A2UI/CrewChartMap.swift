import A2UICore
import Charts
import MapKit
import SwiftUI

private struct ChartPoint: Identifiable {
    let id: String
    let label: String
    let series: String
    let value: Double
}

struct CrewChart: View {
    let node: Node

    var body: some View {
        let kind = node.string(for: "kind") ?? "bar"
        let unit = node.string(for: "unit") ?? ""
        let labels = (node.array(for: "labels") ?? []).map { $0 as? String ?? "" }
        let numbers = { (values: [any Resolved]?) in (values ?? []).map { $0 as? Double ?? 0 } }
        let named = (node.array(for: "series") ?? []).compactMap { $0 as? ResolvedDictionary }.map { series in
            (name: series.string(for: "name") ?? "", values: numbers((series["values"] as? ResolvedArray)?.elements))
        }
        let series = named.isEmpty ? [(name: unit, values: numbers(node.array(for: "values")))] : named
        let points = series.flatMap { series in
            zip(labels, series.values).enumerated().map { index, pair in
                ChartPoint(id: "\(series.name)-\(index)", label: pair.0, series: series.name, value: pair.1)
            }
        }
        Chart(points) { point in
            if kind == "line" {
                LineMark(x: .value("Label", point.label), y: .value(unit, point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                PointMark(x: .value("Label", point.label), y: .value(unit, point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbolSize(32)
            } else if kind == "area" {
                AreaMark(x: .value("Label", point.label), y: .value(unit, point.value), series: .value("Series", point.series), stacking: .unstacked)
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.catmullRom)
                    .opacity(0.32)
                LineMark(x: .value("Label", point.label), y: .value(unit, point.value), series: .value("Series", point.series))
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                BarMark(x: .value("Label", point.label), y: .value(unit, point.value), width: .ratio(series.count > 1 ? 0.8 : 0.6))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
                    .clipShape(.rect(cornerRadius: 4))
            }
        }
        .chartForegroundStyleScale(range: series.count > 1 ? [Color.accentColor, .orange, .teal, .pink, .purple] : [Color.accentColor])
        .chartLegend(series.count > 1 ? .visible : .hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .chartYAxisLabel(unit)
        .frame(height: 200)
        .accessibilityLabel(labels.joined(separator: ", "))
    }
}

private final class MapSnapshot {
    let image: Image
    let size: CGSize
    let points: [CGPoint]

    init(image: Image, size: CGSize, points: [CGPoint]) {
        self.image = image
        self.size = size
        self.points = points
    }
}

@MainActor private let mapSnapshots = {
    let cache = NSCache<NSString, MapSnapshot>()
    cache.countLimit = 32
    return cache
}()

struct CrewMap: View {
    let node: Node
    @Environment(\.colorScheme) private var colorScheme
    @State private var width: CGFloat = 0
    @State private var snapshot: MapSnapshot?

    var body: some View {
        let markers = (node.array(for: "markers") ?? []).compactMap { $0 as? ResolvedDictionary }.compactMap { marker -> (title: String, coordinate: CLLocationCoordinate2D)? in
            guard let latitude = marker.double(for: "latitude"), let longitude = marker.double(for: "longitude") else { return nil }
            return (marker.string(for: "title") ?? "", CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        let region = (node.properties["region"] as? ResolvedDictionary).flatMap { region -> MKCoordinateRegion? in
            guard let latitude = region.double(for: "latitude"), let longitude = region.double(for: "longitude") else { return nil }
            let span = region.double(for: "span") ?? 0.05
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
        }
        let latitudes = markers.map(\.coordinate.latitude)
        let longitudes = markers.map(\.coordinate.longitude)
        let fitted = latitudes.min().flatMap { south in
            let latitudeSpan = max(0.008, ((latitudes.max() ?? south) - south) * 2.4)
            let west = longitudes.min() ?? 0
            let east = longitudes.max() ?? west
            let center = CLLocationCoordinate2D(latitude: ((latitudes.max() ?? south) + south) / 2 - latitudeSpan * 0.08, longitude: (west + east) / 2)
            return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: max(0.008, (east - west) * 1.6)))
        }
        let shown = region ?? fitted
        let size = CGSize(width: width.rounded(), height: 240)
        let key = ([shown.map { "\($0.center.latitude),\($0.center.longitude),\($0.span.latitudeDelta),\($0.span.longitudeDelta)" } ?? "world", "\(size.width)", "\(colorScheme)"]
            + markers.map { "\($0.title)@\($0.coordinate.latitude),\($0.coordinate.longitude)" }).joined(separator: "|")
        let openInMaps = {
            _ = MKMapItem.openMaps(with: markers.map { marker in
                let item = MKMapItem(location: CLLocation(latitude: marker.coordinate.latitude, longitude: marker.coordinate.longitude), address: nil)
                item.name = marker.title
                return item
            })
        }
        Button(action: openInMaps) {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                if let snapshot {
                    ZStack(alignment: .topLeading) {
                        snapshot.image
                        ForEach(snapshot.points.indices, id: \.self) { index in
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                                .shadow(radius: 2, y: 1)
                                .overlay(alignment: .top) {
                                    Text(markers.indices.contains(index) ? markers[index].title : "")
                                        .font(.caption2.weight(.semibold))
                                        .fixedSize()
                                        .shadow(color: .black.opacity(0.25), radius: 2)
                                        .offset(y: 32)
                                }
                                .position(snapshot.points[index])
                        }
                    }
                    .frame(width: snapshot.size.width, height: snapshot.size.height)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(markers.map(\.title).joined(separator: ", "))
        .accessibilityHint("Opens in Maps")
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .task(id: key) {
            guard size.width > 0 else { return }
            if let cached = mapSnapshots.object(forKey: key as NSString) {
                snapshot = cached
                return
            }
            let configuration = MKStandardMapConfiguration()
            configuration.pointOfInterestFilter = .excludingAll
            let options = MKMapSnapshotter.Options()
            options.preferredConfiguration = configuration
            options.size = size
            if let shown { options.region = shown }
            #if os(macOS)
            options.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            #else
            options.traitCollection = UITraitCollection { $0.userInterfaceStyle = colorScheme == .dark ? .dark : .light }
            #endif
            guard let result = try? await MKMapSnapshotter(options: options).start() else { return }
            #if os(macOS)
            let image = Image(nsImage: result.image)
            #else
            let image = Image(uiImage: result.image)
            #endif
            let fresh = MapSnapshot(image: image, size: size, points: markers.map { result.point(for: $0.coordinate) })
            mapSnapshots.setObject(fresh, forKey: key as NSString)
            snapshot = fresh
        }
        .overlay(alignment: .bottomTrailing) {
            Button("Open in Maps", systemImage: "map", action: openInMaps)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .padding(8)
        }
    }
}
