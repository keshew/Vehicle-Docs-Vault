import SwiftUI

struct OnboardingArtwork: View {
    var page: Int
    var body: some View {
        ZStack {
            Color.vaultNavy
            GeometryReader { geometry in
                Path { path in
                    for index in 0..<8 {
                        let y = CGFloat(index) * geometry.size.height / 7
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    for index in 0..<7 {
                        let x = CGFloat(index) * geometry.size.width / 6
                        path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                }.stroke(Color.white.opacity(0.025), lineWidth: 0.5)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text(["THE PERSONAL ARCHIVE", "THE DOCUMENT COLLECTION", "AN EXACT RECORD", "THE SERVICE JOURNAL", "YOUR PRIVATE GARAGE"][page]).font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.6); Spacer(); Image(systemName: "square.stack.3d.up").font(.system(size: 13, weight: .ultraLight)) }.foregroundStyle(Color.vaultChampagne).padding(.bottom, 20)
                Group {
                    switch page {
                    case 0: AutomotiveSilhouette().overlay(alignment: .bottomTrailing) { Image(systemName: "lock").font(.system(size: 13, weight: .ultraLight)).foregroundStyle(Color.vaultChampagne).padding(12).background(Circle().stroke(Color.vaultChampagne.opacity(0.3))).offset(y: -15) }
                    case 1: documents
                    case 2: specifications
                    case 3: service
                    default: collection
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack { Rectangle().fill(Color.vaultChampagne.opacity(0.3)).frame(width: 22, height: 1); Text("CONSIDER EVERY DETAIL").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(1.8); Spacer(); Text(String(format: "%02d", page + 1)).font(.system(size: 8, design: .monospaced)) }.foregroundStyle(.white.opacity(0.4)).padding(.top, 18)
            }.padding(24)
        }.clipShape(RoundedRectangle(cornerRadius: 27)).overlay(RoundedRectangle(cornerRadius: 27).stroke(Color.vaultChampagne.opacity(0.16), lineWidth: 1)).accessibilityHidden(true)
    }
    var documents: some View {
        ZStack {
            document("Registration", symbol: "doc.text").rotationEffect(.degrees(-9)).offset(x: -22, y: -8).opacity(0.6)
            document("Insurance", symbol: "shield.lefthalf.filled").rotationEffect(.degrees(5)).offset(x: 18, y: 10)
        }.padding(.vertical, 5)
    }
    func document(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Image(systemName: symbol).font(.system(size: 21, weight: .ultraLight)); Spacer(); Image(systemName: "checkmark.circle").font(.system(size: 13, weight: .ultraLight)) }.foregroundStyle(Color.vaultChampagne)
            Text(title).font(.vaultDisplay(25)).foregroundStyle(.white)
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            Text("KEPT IN ONE PLACE").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.white.opacity(0.4))
        }.padding(20).frame(width: 205).background(Color(red: 0.13, green: 0.17, blue: 0.20), in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.vaultChampagne.opacity(0.2)))
    }
    var specifications: some View {
        VStack(spacing: 0) {
            ForEach(Array([("VIN & identification", "number"), ("Engine & transmission", "gearshape.2"), ("Technical specifications", "list.bullet.rectangle")].enumerated()), id: \.offset) { index, item in
                HStack(spacing: 15) { Text(String(format: "%02d", index + 1)).font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.vaultChampagne); Text(item.0).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)); Spacer(); Image(systemName: item.1).font(.system(size: 17, weight: .ultraLight)).foregroundStyle(Color.vaultChampagne) }.padding(.vertical, 18)
                if index != 2 { Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5) }
            }
        }
    }
    var service: some View {
        HStack(spacing: 26) {
            TireIllustration().frame(width: 75, height: 95)
            VStack(alignment: .leading, spacing: 18) {
                Text("Every change.\nA clear history.").font(.vaultDisplay(26)).foregroundStyle(.white)
                ForEach(["Parts & replacements", "Tires & seasonal changes"], id: \.self) { text in HStack(spacing: 8) { Circle().fill(Color.vaultChampagne).frame(width: 3, height: 3); Text(text).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)) } }
            }
        }
    }
    var collection: some View {
        VStack(spacing: 11) {
            ForEach(0..<3) { index in
                HStack(spacing: 14) {
                    Image(systemName: index == 1 ? "bicycle" : "car.side").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(Color.vaultChampagne).frame(width: 44)
                    VStack(alignment: .leading, spacing: 6) { Text(["Daily drives", "Weekend escapes", "The collection"][index]).font(.vaultDisplay(20)).foregroundStyle(.white); Text("ITS OWN SPACE. ITS OWN STORY.").font(.system(size: 6, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.white.opacity(0.4)) }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(Color.vaultChampagne)
                }.padding(14).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.08)))
            }
        }
    }
}
