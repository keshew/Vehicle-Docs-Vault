import SwiftUI
import UIKit

struct AutomotiveSilhouette: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Ellipse().fill(Color.white.opacity(0.055)).frame(width: width * 0.8, height: height * 0.30).blur(radius: 20).offset(y: height * 0.06)
                Ellipse().fill(Color.black.opacity(0.7)).frame(width: width * 0.82, height: height * 0.07).position(x: width * 0.5, y: height * 0.82)
                Path { path in path.move(to: CGPoint(x: width * 0.03, y: height * 0.84)); path.addLine(to: CGPoint(x: width * 0.97, y: height * 0.84)) }.stroke(Color.vaultChampagne.opacity(0.12), lineWidth: 0.6)
                ForEach([CGFloat(0.245), CGFloat(0.785)], id: \.self) { x in
                    ZStack {
                        Circle().fill(Color(red: 0.025, green: 0.035, blue: 0.045))
                        Circle().stroke(Color(white: 0.25), lineWidth: 1).padding(2)
                        Circle().fill(LinearGradient(colors: [Color(white: 0.6), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(5)
                        Circle().fill(Color(white: 0.08)).padding(7)
                        ForEach(0..<10) { spoke in Rectangle().fill(Color(white: 0.6)).frame(width: 1.1, height: width * 0.075).rotationEffect(.degrees(Double(spoke) * 18)) }
                        Circle().fill(Color(white: 0.4)).frame(width: 5, height: 5)
                    }.frame(width: width * 0.125, height: width * 0.125).position(x: width * x, y: height * 0.73)
                }
                Coachwork().fill(LinearGradient(stops: [.init(color: Color(white: 0.48), location: 0), .init(color: Color(red: 0.17, green: 0.22, blue: 0.26), location: 0.35), .init(color: Color(red: 0.055, green: 0.09, blue: 0.12), location: 0.68), .init(color: Color(white: 0.24), location: 1)], startPoint: .top, endPoint: .bottom))
                Coachwork().stroke(Color.vaultChampagne.opacity(0.42), lineWidth: 0.7)
                VehicleGlass().fill(LinearGradient(colors: [Color(red: 0.17, green: 0.23, blue: 0.27), Color(red: 0.025, green: 0.055, blue: 0.08)], startPoint: .top, endPoint: .bottom))
                VehicleGlass().stroke(Color.white.opacity(0.35), lineWidth: 0.6)
                Path { path in
                    path.move(to: CGPoint(x: width * 0.12, y: height * 0.55)); path.addQuadCurve(to: CGPoint(x: width * 0.91, y: height * 0.56), control: CGPoint(x: width * 0.55, y: height * 0.59))
                    path.move(to: CGPoint(x: width * 0.52, y: height * 0.33)); path.addLine(to: CGPoint(x: width * 0.53, y: height * 0.50))
                    path.move(to: CGPoint(x: width * 0.52, y: height * 0.55)); path.addLine(to: CGPoint(x: width * 0.53, y: height * 0.71))
                    path.move(to: CGPoint(x: width * 0.57, y: height * 0.56)); path.addLine(to: CGPoint(x: width * 0.60, y: height * 0.56))
                }.stroke(Color.white.opacity(0.24), lineWidth: 0.65)
                Group {
                    Capsule().fill(Color(red: 0.91, green: 0.36, blue: 0.26)).frame(width: width * 0.035, height: 2).position(x: width * 0.10, y: height * 0.57)
                    Capsule().fill(Color(white: 0.95)).frame(width: width * 0.055, height: 2).rotationEffect(.degrees(-5)).position(x: width * 0.90, y: height * 0.56)
                }
            }
        }.accessibilityHidden(true)
    }
}

private struct Coachwork: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.width * x, y: rect.height * y) }
        var p = Path()
        p.move(to: point(0.06, 0.65)); p.addQuadCurve(to: point(0.12, 0.51), control: point(0.07, 0.51))
        p.addLine(to: point(0.29, 0.47)); p.addQuadCurve(to: point(0.44, 0.29), control: point(0.37, 0.29))
        p.addQuadCurve(to: point(0.64, 0.31), control: point(0.55, 0.25)); p.addLine(to: point(0.77, 0.47))
        p.addQuadCurve(to: point(0.93, 0.55), control: point(0.90, 0.49)); p.addLine(to: point(0.96, 0.66))
        p.addQuadCurve(to: point(0.88, 0.73), control: point(0.96, 0.72)); p.addLine(to: point(0.86, 0.73))
        p.addCurve(to: point(0.71, 0.73), control1: point(0.86, 0.48), control2: point(0.71, 0.48))
        p.addLine(to: point(0.32, 0.73)); p.addCurve(to: point(0.17, 0.73), control1: point(0.32, 0.48), control2: point(0.17, 0.48))
        p.addQuadCurve(to: point(0.06, 0.65), control: point(0.06, 0.74)); p.closeSubpath()
        return p
    }
}

private struct VehicleGlass: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.width * x, y: rect.height * y) }
        var p = Path()
        p.move(to: point(0.34, 0.475)); p.addQuadCurve(to: point(0.45, 0.325), control: point(0.40, 0.33))
        p.addQuadCurve(to: point(0.63, 0.345), control: point(0.55, 0.29)); p.addLine(to: point(0.735, 0.49))
        p.closeSubpath(); return p
    }
}

struct VehicleShowcaseCard: View {
    @EnvironmentObject var store: VaultStore
    var vehicle: Vehicle
    var compact = false
    var photo: VaultAttachment? {
        guard let id = vehicle.coverID, let file = store.database.attachments.first(where: { $0.id == id }) else { return nil }
        return file
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) { Circle().fill(Color.vaultChampagne).frame(width: 4, height: 4); Text(vehicle.type.uppercased()).tracking(2) }.font(.system(size: 9, weight: .medium))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .light))
            }.foregroundStyle(Color.vaultChampagne).padding(.bottom, 18)
            Text(vehicle.title).font(.vaultDisplay(compact ? 28 : 34)).tracking(-0.9).foregroundStyle(.white).multilineTextAlignment(.leading)
            Text(vehicle.subtitle.isEmpty ? "Your personal vehicle archive" : vehicle.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).padding(.top, 7)
            Group {
                if let photo {
                    VaultMediaImage(url: store.fileURL(photo), pixels: 1400) { AutomotiveSilhouette() }
                        .frame(height: compact ? 125 : 175).clipShape(RoundedRectangle(cornerRadius: 15)).padding(.vertical, 18)
                }
                else if vehicle.type == "Car" || vehicle.type == "Other" { AutomotiveSilhouette().frame(height: compact ? 125 : 165).padding(.horizontal, -12) }
                else { Image(systemName: vehicle.type == "Motorcycle" ? "bicycle" : "truck.box").font(.system(size: 76, weight: .ultraLight)).foregroundStyle(Color.vaultChampagne.opacity(0.65)).frame(maxWidth: .infinity).frame(height: compact ? 125 : 165) }
            }
            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("LICENSE PLATE").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.7).foregroundStyle(.white.opacity(0.4))
                    Text(vehicle.plate.isEmpty ? "Not added" : vehicle.plate).font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(1.7).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Text("ODOMETER").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.7).foregroundStyle(.white.opacity(0.4))
                    Text(vehicle["mileage"].isEmpty ? "—" : "\(vehicle["mileage"]) \(vehicle["distanceUnit"].isEmpty ? store.distanceSuffix : vehicle["distanceUnit"])").font(.system(size: 13, weight: .regular, design: .rounded)).foregroundStyle(Color.vaultChampagne)
                }
            }.padding(.top, 18)
        }.padding(25).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.10, green: 0.15, blue: 0.19), .vaultNavy, Color(red: 0.025, green: 0.045, blue: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 27))
            .overlay(RoundedRectangle(cornerRadius: 27).stroke(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.025), Color.vaultChampagne.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: Color.vaultNavy.opacity(0.16), radius: 22, x: 0, y: 12)
    }
}
