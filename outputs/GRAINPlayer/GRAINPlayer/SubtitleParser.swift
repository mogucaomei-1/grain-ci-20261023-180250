import Foundation

// MARK: - 字幕解析器 (支持 SRT 与 VTT 格式)

public enum SubtitleParser {
    public static func parse(content: String, trackTitle: String) -> SubtitleTrack {
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var items: [SubtitleItem] = []
        var currentIndex = 1
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // 跳过空行或 WEBVTT 头部
            if line.isEmpty || line.hasPrefix("WEBVTT") || line.hasPrefix("NOTE") {
                i += 1
                continue
            }

            // 判断是否包含时间轴标记 "-->"
            if line.contains("-->") {
                if let (start, end) = parseTimeRange(line) {
                    i += 1
                    var textLines: [String] = []
                    while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        textLines.append(lines[i].trimmingCharacters(in: .whitespaces))
                        i += 1
                    }
                    let cleanedText = sanitizeText(textLines.joined(separator: "\n"))
                    if !cleanedText.isEmpty {
                        items.append(SubtitleItem(index: currentIndex, startTime: start, endTime: end, text: cleanedText))
                        currentIndex += 1
                    }
                }
            } else if i + 1 < lines.count && lines[i + 1].contains("-->") {
                // 当前行是序号，下一行是时间戳
                let timeLine = lines[i + 1]
                if let (start, end) = parseTimeRange(timeLine) {
                    i += 2
                    var textLines: [String] = []
                    while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        textLines.append(lines[i].trimmingCharacters(in: .whitespaces))
                        i += 1
                    }
                    let cleanedText = sanitizeText(textLines.joined(separator: "\n"))
                    if !cleanedText.isEmpty {
                        items.append(SubtitleItem(index: currentIndex, startTime: start, endTime: end, text: cleanedText))
                        currentIndex += 1
                    }
                }
            } else {
                i += 1
            }
        }

        return SubtitleTrack(id: UUID().uuidString, title: trackTitle, isExternal: true, items: items)
    }

    /// 解析 "00:01:20,000 --> 00:01:24,400"
    private static func parseTimeRange(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        guard let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return (start, end)
    }

    /// 解析时间戳为秒数 (支持 00:00:00,000 或 00:00:00.000 或 00:00.000)
    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let clean = raw.components(separatedBy: " ")[0]
            .replacingOccurrences(of: ",", with: ".")

        let subParts = clean.components(separatedBy: ".")
        let timeParts = subParts[0].components(separatedBy: ":")
        let millis: Double = subParts.count > 1 ? (Double("0." + subParts[1]) ?? 0) : 0

        if timeParts.count == 3 {
            guard let h = Double(timeParts[0]),
                  let m = Double(timeParts[1]),
                  let s = Double(timeParts[2]) else { return nil }
            return h * 3600 + m * 60 + s + millis
        } else if timeParts.count == 2 {
            guard let m = Double(timeParts[0]),
                  let s = Double(timeParts[1]) else { return nil }
            return m * 60 + s + millis
        }
        return nil
    }

    /// 清除 HTML/样式标签，如 <i>, <b>, <font color="..."> 等
    private static func sanitizeText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\{[^\\}]+\\}", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 查找指定时刻应显示的字幕内容
    public static func currentSubtitle(at time: TimeInterval, in items: [SubtitleItem]) -> String? {
        // 由于字幕按时间正序，可直接查找覆盖当前时间的条目
        for item in items {
            if time >= item.startTime && time <= item.endTime {
                return item.text
            }
        }
        return nil
    }
}
