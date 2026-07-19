import UIKit

/// The camera card — a designed share frame the user chooses (never a
/// watermark; the bare export stays unmarked). Also renders the two-light
/// pair used for screenshots and the press kit.
enum LightTestCard {

  // MARK: Palette (fixed — the card is a printed object, not a themed view)

  /// near-black paper `#111110`
  private static let paper = UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x10 / 255, alpha: 1)
  /// the film-frame edge around the photograph
  private static let frameHairline = UIColor.white.withAlphaComponent(0.12)
  /// secondary copy (exif line, decision notes)
  private static let inkSoft = UIColor.white.withAlphaComponent(0.62)
  private static let pillStroke = UIColor.white.withAlphaComponent(0.30)

  /// The stock's catalog frame number, e.g. `LM·16` for the 16th camera in
  /// `Stock.all` (1-based, two digits).
  static func lmIndex(of stock: Stock) -> String {
    let index = Stock.all.firstIndex(where: { $0.id == stock.id }) ?? 0
    return String(format: "LM·%02d", index + 1)
  }

  // MARK: Single mode — the user-facing share card (1080 × 1920 story ratio)

  static func single(photo: UIImage, stock: Stock, decision: String?) -> UIImage {
    let canvas = CGSize(width: 1080, height: 1920)
    return renderer(for: canvas).image { _ in
      paper.setFill()
      UIBezierPath(rect: CGRect(origin: .zero, size: canvas)).fill()

      // the photograph, aspect-fit inside the frame area (48pt side margins)
      let frameArea = CGRect(x: 48, y: 168, width: 984, height: 1312)
      let photoRect = aspectFit(photo.size, in: frameArea)
      photo.draw(in: photoRect)
      strokeHairline(around: photoRect)

      // footer block, left-aligned, 40pt under the photograph
      let textWidth = canvas.width - 96
      var cursorY = photoRect.maxY + 40
      cursorY = draw(
        "\(stock.name.uppercased())  ·  \(lmIndex(of: stock))",
        font: .monospacedSystemFont(ofSize: 34, weight: .bold),
        color: .white,
        at: CGPoint(x: 48, y: cursorY), width: textWidth, maxLines: 1
      )
      cursorY = draw(
        stock.exif,
        font: .monospacedSystemFont(ofSize: 26, weight: .regular),
        color: inkSoft,
        at: CGPoint(x: 48, y: cursorY + 12), width: textWidth, maxLines: 1
      )
      if let decision {
        draw(
          decision,
          font: .systemFont(ofSize: 26),
          color: inkSoft,
          at: CGPoint(x: 48, y: cursorY + 12), width: textWidth, maxLines: 2
        )
      }

      drawPill(in: canvas)
    }
  }

  // MARK: Pair mode — the "two lights, one camera" proof (2160 × 1350)

  static func pair(
    left: (photo: UIImage, decision: String?),
    right: (photo: UIImage, decision: String?),
    stock: Stock
  ) -> UIImage {
    let canvas = CGSize(width: 2160, height: 1350)
    return renderer(for: canvas).image { _ in
      paper.setFill()
      UIBezierPath(rect: CGRect(origin: .zero, size: canvas)).fill()

      // the stock line once, centered above both frames
      drawCentered(
        "\(stock.name.uppercased()) · \(lmIndex(of: stock)) — one camera, two lights",
        font: .monospacedSystemFont(ofSize: 30, weight: .bold),
        color: .white,
        centerX: canvas.width / 2, y: 48
      )

      // two frame areas: 48pt outer margins, 48pt gutter
      let areas = [
        CGRect(x: 48, y: 128, width: 1008, height: 1088),
        CGRect(x: 1104, y: 128, width: 1008, height: 1088),
      ]
      for (area, panel) in zip(areas, [left, right]) {
        let photoRect = aspectFit(panel.photo.size, in: area)
        panel.photo.draw(in: photoRect)
        strokeHairline(around: photoRect)
        if let decision = panel.decision {
          draw(
            decision,
            font: .systemFont(ofSize: 24),
            color: inkSoft,
            at: CGPoint(x: area.minX, y: area.maxY + 16), width: area.width, maxLines: 2
          )
        }
      }

      drawPill(in: canvas)
    }
  }

  // MARK: Drawing helpers (deterministic; scale pinned to 1)

  private static func renderer(for canvas: CGSize) -> UIGraphicsImageRenderer {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: canvas, format: format)
  }

  private static func aspectFit(_ size: CGSize, in area: CGRect) -> CGRect {
    guard size.width > 0, size.height > 0 else { return area }
    let scale = min(area.width / size.width, area.height / size.height)
    let fitted = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(
      x: area.midX - fitted.width / 2,
      y: area.midY - fitted.height / 2,
      width: fitted.width,
      height: fitted.height
    )
  }

  private static func strokeHairline(around rect: CGRect) {
    let edge = UIBezierPath(rect: rect)
    edge.lineWidth = 1
    frameHairline.setStroke()
    edge.stroke()
  }

  /// Draws `text` into a rect of exactly `maxLines` line heights (wrapping,
  /// tail-truncated) and returns the rect's maxY as the next cursor position.
  @discardableResult
  private static func draw(
    _ text: String,
    font: UIFont,
    color: UIColor,
    at origin: CGPoint,
    width: CGFloat,
    maxLines: Int
  ) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    let rect = CGRect(
      x: origin.x, y: origin.y,
      width: width, height: ceil(font.lineHeight * CGFloat(maxLines))
    )
    (text as NSString).draw(
      with: rect,
      options: [.usesLineFragmentOrigin],
      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
      context: nil
    )
    return rect.maxY
  }

  private static func drawCentered(
    _ text: String,
    font: UIFont,
    color: UIColor,
    centerX: CGFloat,
    y: CGFloat
  ) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(at: CGPoint(x: centerX - size.width / 2, y: y), withAttributes: attributes)
  }

  /// `SHOT ON LENSMOOD` — stroked capsule, transparent fill, bottom-right
  /// with 48pt margins, padding 14×8.
  private static func drawPill(in canvas: CGSize) {
    let text = "SHOT ON LENSMOOD" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .semibold),
      .foregroundColor: UIColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    let pill = CGRect(
      x: canvas.width - 48 - ceil(textSize.width) - 28,
      y: canvas.height - 48 - ceil(textSize.height) - 16,
      width: ceil(textSize.width) + 28,
      height: ceil(textSize.height) + 16
    )
    let capsule = UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2)
    capsule.lineWidth = 1
    pillStroke.setStroke()
    capsule.stroke()
    text.draw(at: CGPoint(x: pill.minX + 14, y: pill.minY + 8), withAttributes: attributes)
  }
}
