import Foundation

public enum CompositionFilter {
    public static func baseGraph(ratio: ExportRatio, layout: ResolvedLayout) -> [String] {
        let size = ratio.outputSize
        switch layout {
        case .fit:
            return fitGraph(size: size, crop: nil)
        case let .face(crop):
            return fitGraph(size: size, crop: crop)
        case let .stack(face, demo, style):
            return stackGraph(size: size, face: face, demo: demo, style: style)
        }
    }

    public static func stackMetrics(size: VideoSize, style: StackStyle) -> (
        faceHeight: Int,
        faceY: Int,
        demoMaxWidth: Int,
        demoMaxHeight: Int,
        demoY: Int
    ) {
        let minDemo = 220
        let faceHeight = PixelMath.even(
            min(Int((Double(size.height) * style.faceBand).rounded()), size.height - minDemo)
        )
        let faceY = PixelMath.even(max(0, size.height - faceHeight))
        let demoY = style.demoTopPadding
        let demoMaxWidth = PixelMath.even(max(160, size.width - style.demoSidePadding * 2))
        let demoMaxHeight = PixelMath.even(max(160, faceY + style.demoOverlap - demoY))
        return (faceHeight, faceY, demoMaxWidth, demoMaxHeight, demoY)
    }

    private static func fitGraph(size: VideoSize, crop: CropPlan?) -> [String] {
        let prefix = crop.map { "crop=\($0.width):\($0.height):\($0.x):\($0.y)," } ?? ""
        return [
            "[0:v]\(prefix)split=2[bg][fg]",
            "[bg]scale=\(size.width):\(size.height):force_original_aspect_ratio=increase,crop=\(size.width):\(size.height),gblur=sigma=32,eq=brightness=-0.06:saturation=1.12[bgv]",
            "[fg]scale=\(size.width):\(size.height):force_original_aspect_ratio=decrease[fgv]",
            "[bgv][fgv]overlay=(W-w)/2:(H-h)/2,setsar=1[v0]"
        ]
    }

    private static func stackGraph(
        size: VideoSize,
        face: CropPlan,
        demo: CropPlan,
        style: StackStyle
    ) -> [String] {
        let metrics = stackMetrics(size: size, style: style)
        let radius = style.cornerRadius
        return [
            "[0:v]split=3[bg][face][demo]",
            "[bg]scale=\(size.width):\(size.height):force_original_aspect_ratio=increase,crop=\(size.width):\(size.height),gblur=sigma=28,eq=brightness=-0.08:saturation=1.08[bgv]",
            "[face]crop=\(face.width):\(face.height):\(face.x):\(face.y),scale=\(size.width):\(metrics.faceHeight):force_original_aspect_ratio=increase,crop=\(size.width):\(metrics.faceHeight)[facev]",
            "[demo]crop=\(demo.width):\(demo.height):\(demo.x):\(demo.y),scale=\(metrics.demoMaxWidth):\(metrics.demoMaxHeight):force_original_aspect_ratio=decrease,format=rgba,\(roundedCornerFilter(radius: radius))[demov]",
            "[bgv][facev]overlay=0:\(metrics.faceY)[v1]",
            "[v1][demov]overlay=(W-w)/2:\(metrics.demoY),setsar=1[v0]"
        ]
    }

    public static func roundedCornerFilter(radius: Int) -> String {
        let r = max(8, radius)
        let alpha =
            "if(gt(abs(W/2-X),W/2-\(r))*gt(abs(H/2-Y),H/2-\(r)),if(lte(hypot(abs(W/2-X)-(W/2-\(r)),abs(H/2-Y)-(H/2-\(r))),\(r)),255,0),255)"
        return "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='\(alpha)'"
    }
}
