import SwiftUI
import Charts

struct VaultMonthValue: Identifiable {
    var date: Date
    var count: Int
    var id: Date { date }
}

struct RecordActivityChart: View {
    @EnvironmentObject var store: VaultStore
    var vehicleID: UUID?
    var replacementsOnly = false
    @State private var selected: Date?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 140
    private var buckets: [VaultMonthValue] {
        let calendar = Calendar(identifier: .gregorian)
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let records = store.database.records.filter { (vehicleID == nil || $0.vehicleID == vehicleID) && (!replacementsOnly || $0.kind == .replacement || $0.kind == .tireChange) }
        return (-5...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset, to: month) else { return nil }
            return VaultMonthValue(date: date, count: records.filter { calendar.isDate(replacementsOnly ? $0.date : $0.created, equalTo: date, toGranularity: .month) }.count)
        }
    }
    var chosen: VaultMonthValue? { selected.flatMap { date in buckets.first { Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month) } } }
    var total: Int { buckets.reduce(0) { $0 + $1.count } }
    var maximum: Int { max(3, buckets.map(\.count).max() ?? 0) }
    var body: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(replacementsOnly ? "REPLACEMENT ACTIVITY" : "RECORD ACTIVITY").font(.vaultEyebrow).tracking(1.7).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(chosen?.count ?? total)").font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(Color.vaultInk)
                            Text(replacementsOnly ? "changes" : "records added").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(chosen.map { $0.date.formatted(.dateTime.month(.abbreviated).year().locale(Locale(identifier: "en_US"))) } ?? "LAST 6 MONTHS").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Color.vaultGold).padding(.horizontal, 10).padding(.vertical, 7).background(Color.vaultGold.opacity(0.07), in: Capsule())
                }
                Chart {
                    ForEach(buckets) { bucket in
                        BarMark(x: .value("Month", bucket.date, unit: .month), y: .value("Records", bucket.count), width: .ratio(0.45))
                            .foregroundStyle(LinearGradient(colors: [Color.vaultChampagne, Color.vaultGold], startPoint: .top, endPoint: .bottom))
                            .cornerRadius(5)
                            .opacity(selected == nil || chosen?.date == bucket.date ? 1 : 0.3)
                    }
                    if let chosen { RuleMark(x: .value("Selected month", chosen.date, unit: .month)).foregroundStyle(Color.vaultGold.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])) }
                }
                .chartYScale(domain: 0...maximum)
                .chartXAxis { AxisMarks(values: buckets.map(\.date)) { value in AxisValueLabel { if let date = value.as(Date.self) { Text(date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "en_US")))).font(.system(size: 10)).foregroundStyle(.secondary) } } } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color.vaultLine); AxisValueLabel().font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) } }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                            guard abs(value.translation.width) >= abs(value.translation.height) else { selected = nil; return }
                            let x = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                            guard (0...proxy.plotAreaSize.width).contains(x) else { return }
                            if let date: Date = proxy.value(atX: x) { selected = date }
                        }.onEnded { _ in selected = nil })
                    }
                }
                .frame(height: chartHeight)
                .accessibilityLabel(replacementsOnly ? "Replacement records over six months" : "Records added over six months")
                HStack(spacing: 7) {
                    Circle().fill(Color.vaultGold).frame(width: 5, height: 5)
                    Text(total == 0 ? "Your first record will start this chart." : "Touch the chart to explore each month.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DocumentStatusCard: View {
    @EnvironmentObject var store: VaultStore
    var vehicleID: UUID
    var compact = false
    var documents: [VaultRecord] { store.records(.document, vehicleID: vehicleID) }
    var valid: Int { documents.filter { $0.computedStatus == "Active" || $0.computedStatus == "No Expiration" }.count }
    var due: Int { documents.filter { $0.computedStatus == "Expiring Soon" }.count }
    var expired: Int { documents.filter { $0.computedStatus == "Expired" }.count }
    let colors: [Color] = [.vaultGold, Color(red: 0.75, green: 0.49, blue: 0.25), Color(red: 0.66, green: 0.28, blue: 0.26)]
    var counts: [Int] { [valid, due, expired] }
    var body: some View {
        VaultCard {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Text("DOCUMENT STATUS").font(.vaultEyebrow).tracking(1.7).foregroundStyle(.secondary); Spacer(); Image(systemName: "doc.text").font(.system(size: 14, weight: .light)).foregroundStyle(Color.vaultGold) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 25) { statusRing; statusLegend.frame(minWidth: 105) }
                    VStack(spacing: 22) { statusRing; statusLegend }.frame(maxWidth: .infinity)
                }
                Text(documents.isEmpty ? "Add documents to see their status at a glance." : "Current includes documents without an expiration date.").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }
    private var statusRing: some View {
        ZStack {
            Circle().stroke(Color.vaultGold.opacity(0.09), lineWidth: 10)
            ForEach(0..<3) { index in
                if counts[index] > 0 { Circle().trim(from: start(index), to: end(index)).stroke(colors[index], style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90)) }
            }
            VStack(spacing: 4) { Text("\(documents.count)").font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit(); Text("DOCUMENTS").font(.system(size: 8, weight: .medium)).tracking(1.3).foregroundStyle(.secondary) }
        }.frame(width: compact ? 100 : 118, height: compact ? 100 : 118).padding(5).accessibilityElement(children: .ignore).accessibilityLabel("\(documents.count) documents. \(valid) current, \(due) expiring soon, \(expired) expired.")
    }
    private var statusLegend: some View {
        VStack(spacing: 15) { legend("Current", count: valid, color: colors[0]); legend("Due in 30 days", count: due, color: colors[1]); legend("Expired", count: expired, color: colors[2]) }
    }
    func start(_ index: Int) -> CGFloat { CGFloat(counts.prefix(index).reduce(0, +)) / CGFloat(max(1, documents.count)) + (counts[index] == documents.count ? 0 : 0.012) }
    func end(_ index: Int) -> CGFloat { max(start(index), CGFloat(counts.prefix(index + 1).reduce(0, +)) / CGFloat(max(1, documents.count)) - (counts[index] == documents.count ? 0 : 0.012)) }
    func legend(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) { Circle().fill(color).frame(width: 5, height: 5); Text(title).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(minLength: 5); Text("\(count)").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Color.vaultInk) }
    }
}

struct MileagePoint: Identifiable {
    var id: UUID
    var date: Date
    var value: Double
}

struct MileageHistoryCard: View {
    @EnvironmentObject var store: VaultStore
    var vehicle: Vehicle
    @State private var selected: MileagePoint?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 155
    var points: [MileagePoint] {
        var result = store.database.records.compactMap { record -> MileagePoint? in
            guard record.vehicleID == vehicle.id, !record.archived, [.replacement, .tireChange, .part, .tire].contains(record.kind), let mileage = Double(record["mileage"]), mileage.isFinite, mileage >= 0 else { return nil }
            let date = [.part, .tire].contains(record.kind) ? ISO8601DateFormatter().date(from: record["installedDate"]) : record.date
            guard let date else { return nil }
            let unit = record["distanceUnit"].isEmpty ? store.distanceSuffix : record["distanceUnit"]
            return MileagePoint(id: record.id, date: date, value: normalized(mileage, from: unit))
        }
        if let current = Double(vehicle["mileage"]), current.isFinite, current >= 0,
           let date = ISO8601DateFormatter().date(from: vehicle["mileageRecordedAt"]) {
            let unit = vehicle["distanceUnit"].isEmpty ? store.distanceSuffix : vehicle["distanceUnit"]
            result.append(MileagePoint(id: vehicle.id, date: date, value: normalized(current, from: unit)))
        }
        return result.sorted { $0.date < $1.date }
    }
    var body: some View {
        let readings = points
        let minimum = readings.map(\.value).min() ?? 0
        let maximum = readings.map(\.value).max() ?? 0
        let margin = max(100, (maximum - minimum) * 0.15)
        let floorValue = max(0, minimum - margin)
        let ceilingValue = maximum + margin
        return VaultCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("ODOMETER HISTORY").font(.vaultEyebrow).tracking(1.6).foregroundStyle(.secondary)
                    Spacer(); Text(store.distanceSuffix.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Color.vaultGold)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text((selected ?? readings.last).map { $0.value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US"))) } ?? "—").font(.system(size: 36, weight: .light, design: .rounded)).foregroundStyle(Color.vaultInk).monospacedDigit()
                    Text(selected.map { store.date($0.date) } ?? (readings.isEmpty ? "no readings yet" : "last recorded")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if readings.count >= 2 {
                    Chart {
                        ForEach(readings) { point in
                            AreaMark(x: .value("Date", point.date), yStart: .value("Baseline", floorValue), yEnd: .value("Mileage", point.value)).foregroundStyle(LinearGradient(colors: [Color.vaultBlue.opacity(0.18), Color.vaultBlue.opacity(0.005)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.linear)
                            LineMark(x: .value("Date", point.date), y: .value("Mileage", point.value)).foregroundStyle(Color.vaultBlue).interpolationMethod(.linear).lineStyle(StrokeStyle(lineWidth: 2))
                            PointMark(x: .value("Date", point.date), y: .value("Mileage", point.value)).foregroundStyle(Color.vaultBlue).symbolSize(18)
                        }
                        if let selected { RuleMark(x: .value("Selected", selected.date)).foregroundStyle(Color.vaultGold).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4])); PointMark(x: .value("Date", selected.date), y: .value("Mileage", selected.value)).foregroundStyle(Color.vaultGold).symbolSize(45) }
                    }.chartYScale(domain: floorValue...ceilingValue)
                        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color.vaultLine); AxisValueLabel().font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) } }
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in AxisValueLabel { if let date = value.as(Date.self) { Text(date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_US")))).font(.system(size: 9)).foregroundStyle(.secondary) } } } }
                        .chartOverlay { proxy in GeometryReader { geometry in Rectangle().fill(.clear).contentShape(Rectangle()).simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                            guard abs(value.translation.width) >= abs(value.translation.height) else { selected = nil; return }
                            let x = value.location.x - geometry[proxy.plotAreaFrame].origin.x
                            guard (0...proxy.plotAreaSize.width).contains(x) else { return }
                            if let date: Date = proxy.value(atX: x) { selected = readings.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
                        }.onEnded { _ in selected = nil }) } }.frame(height: chartHeight)
                } else {
                    VStack(alignment: .leading, spacing: 13) {
                        Rectangle().fill(Color.vaultLine).frame(height: 1).overlay(alignment: .leading) { Circle().fill(Color.vaultGold).frame(width: 6, height: 6) }
                        Text("Add mileage to replacement or tire change records to build your odometer history.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    }.padding(.vertical, 20)
                }
                Text("Recorded readings only · No estimates").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
    func normalized(_ value: Double, from: String) -> Double { from == store.distanceSuffix ? value : store.distanceSuffix == "mi" ? value / 1.609344 : value * 1.609344 }
}
