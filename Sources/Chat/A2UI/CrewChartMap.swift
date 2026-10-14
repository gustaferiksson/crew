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

struct CrewMap: View {
    let node: Node

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
        Map(initialPosition: (region ?? fitted).map { .region($0) } ?? .automatic, interactionModes: []) {
            ForEach(markers.indices, id: \.self) { index in
                Marker(markers[index].title, coordinate: markers[index].coordinate)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 240)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            Button("Open in Maps", systemImage: "map") {
                MKMapItem.openMaps(with: markers.map { marker in
                    let item = MKMapItem(location: CLLocation(latitude: marker.coordinate.latitude, longitude: marker.coordinate.longitude), address: nil)
                    item.name = marker.title
                    return item
                })
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(markers.map(\.title).joined(separator: ", "))
    }
}
