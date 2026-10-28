// Minimum iOS 17.
//  The gilt lozenge: a solid upright rhombus, 2:3, alone or as the three-unit asterism (one over two).

import SwiftUI

struct LozengeShape: Shape {
    var asterism = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if asterism {
            // Three 6 × 9 units in a 16 × 19 box.
            let sx = rect.width / 16, sy = rect.height / 19
            for (x, y) in [(5.0, 0.0), (0.0, 10.0), (10.0, 10.0)] {
                path.addPath(Self.unit(in: CGRect(x: rect.minX + x * sx, y: rect.minY + y * sy, width: 6 * sx, height: 9 * sy)))
            }
        } else {
            path.addPath(Self.unit(in: rect))
        }
        return path
    }

    private static func unit(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
        }
    }
}
