import UIKit
import PDFKit

/// Generates a beautifully styled PDF journal export that matches the StillMind design aesthetic.
final class PDFExportService: @unchecked Sendable {
    private let entryRepository: EntryRepository
    private let projectRepository: ProjectRepository

    // Sage-tinted palette for PDF rendering
    private let accentColor = UIColor(red: 0.38, green: 0.61, blue: 0.55, alpha: 1.0)
    private let textColor = UIColor(white: 0.15, alpha: 1.0)
    private let secondaryTextColor = UIColor(white: 0.45, alpha: 1.0)
    private let lightFillColor = UIColor(white: 0.96, alpha: 1.0)
    private let separatorColor = UIColor(white: 0.88, alpha: 1.0)

    init(entryRepository: EntryRepository, projectRepository: ProjectRepository) {
        self.entryRepository = entryRepository
        self.projectRepository = projectRepository
    }

    /// Exports all entries (optionally filtered to a project) as a PDF.
    func exportToPDF(
        projectId: UUID? = nil,
        dateRange: ClosedRange<Date>? = nil
    ) async throws -> URL {
        var entries = try await entryRepository.allEntries()
        let projects = try await projectRepository.allProjects()

        if let projectId {
            entries = entries.filter { $0.projectId == projectId }
        }

        if let range = dateRange {
            entries = entries.filter { range.contains($0.createdAt) }
        }

        entries.sort { $0.createdAt < $1.createdAt }

        let capturedEntries = entries
        let capturedProjects = projects
        let capturedProjectId = projectId
        let pdfData = await Task.detached { [self] in
            self.generatePDF(entries: capturedEntries, projects: capturedProjects, filteredProjectId: capturedProjectId)
        }.value

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillMind-Export-\(dateString(Date())).pdf")
        try pdfData.write(to: tempURL)
        return tempURL
    }

    // MARK: - PDF Generation

    private func generatePDF(
        entries: [VoiceEntry],
        projects: [Project],
        filteredProjectId: UUID?
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let margin: CGFloat = 50
        let contentRect = pageRect.insetBy(dx: margin, dy: margin)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            context.beginPage()
            var y = drawTitlePage(in: contentRect, context: context, filteredProjectId: filteredProjectId, projects: projects, entryCount: entries.count)

            // Mood flow chart
            let moodPoints = entries.compactMap { entry -> (date: Date, mood: String, value: Double)? in
                guard let mood = entry.mood else { return nil }
                return (entry.createdAt, mood, MoodMapping.value(for: mood))
            }

            if !moodPoints.isEmpty {
                if y + 200 > contentRect.maxY {
                    context.beginPage()
                    y = contentRect.minY
                }
                y = drawMoodChart(moodPoints: moodPoints, at: y, in: contentRect, context: context)
                y += 24
            }

            // Group entries by project
            if filteredProjectId != nil {
                for entry in entries {
                    let estimatedHeight = estimateEntryHeight(entry)
                    if y + estimatedHeight > contentRect.maxY {
                        context.beginPage()
                        y = contentRect.minY
                    }
                    y = drawEntry(entry, at: y, in: contentRect, context: context, projects: projects)
                    y += 24
                }
            } else {
                let unassigned = entries.filter { $0.projectId == nil }
                let assigned = entries.filter { $0.projectId != nil }
                let groupedByProject = Dictionary(grouping: assigned) { $0.projectId! }

                if !unassigned.isEmpty {
                    if y + 40 > contentRect.maxY {
                        context.beginPage()
                        y = contentRect.minY
                    }
                    y = drawProjectHeader("General", at: y, in: contentRect, context: context, entryCount: unassigned.count)

                    for entry in unassigned {
                        let estimatedHeight = estimateEntryHeight(entry)
                        if y + estimatedHeight > contentRect.maxY {
                            context.beginPage()
                            y = contentRect.minY
                        }
                        y = drawEntry(entry, at: y, in: contentRect, context: context, projects: projects)
                        y += 24
                    }
                }

                let sortedProjectIds = groupedByProject.keys.sorted { a, b in
                    let nameA = projects.first(where: { $0.id == a })?.name ?? ""
                    let nameB = projects.first(where: { $0.id == b })?.name ?? ""
                    return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
                }

                for projectId in sortedProjectIds {
                    guard let projectEntries = groupedByProject[projectId] else { continue }
                    let projectName = projects.first(where: { $0.id == projectId })?.name ?? "Unknown Project"

                    context.beginPage()
                    y = contentRect.minY

                    let projectMoodPoints = projectEntries.compactMap { entry -> (date: Date, mood: String, value: Double)? in
                        guard let mood = entry.mood else { return nil }
                        return (entry.createdAt, mood, MoodMapping.value(for: mood))
                    }

                    y = drawProjectHeader(projectName, at: y, in: contentRect, context: context, entryCount: projectEntries.count)

                    if !projectMoodPoints.isEmpty {
                        if y + 200 > contentRect.maxY {
                            context.beginPage()
                            y = contentRect.minY
                        }
                        y = drawMoodChart(moodPoints: projectMoodPoints, at: y, in: contentRect, context: context)
                        y += 24
                    }

                    for entry in projectEntries {
                        let estimatedHeight = estimateEntryHeight(entry)
                        if y + estimatedHeight > contentRect.maxY {
                            context.beginPage()
                            y = contentRect.minY
                        }
                        y = drawEntry(entry, at: y, in: contentRect, context: context, projects: projects)
                        y += 24
                    }
                }
            }
        }
    }

    // MARK: - Title Page

    @discardableResult
    private func drawTitlePage(
        in rect: CGRect,
        context: UIGraphicsPDFRendererContext,
        filteredProjectId: UUID?,
        projects: [Project],
        entryCount: Int
    ) -> CGFloat {
        var y = rect.minY + 60

        // App name in accent
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: accentColor
        ]
        "StillMind".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: brandAttrs)
        y += 24

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: textColor
        ]
        "Journal Export".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: titleAttrs)
        y += 40

        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: secondaryTextColor
        ]

        if let projectId = filteredProjectId, let project = projects.first(where: { $0.id == projectId }) {
            "Project: \(project.name)".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: subtitleAttrs)
            y += 20
        }

        "Exported \(dateTimeString(Date()))".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: subtitleAttrs)
        y += 20
        "\(entryCount) reflections".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: subtitleAttrs)
        y += 30

        // Privacy note — warm, not legal
        let noticeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 10),
            .foregroundColor: UIColor(white: 0.60, alpha: 1.0)
        ]
        "This document contains your private reflections. Please store it safely."
            .draw(at: CGPoint(x: rect.minX, y: y), withAttributes: noticeAttrs)
        y += 32

        // Decorative accent line
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: rect.minX, y: y))
        linePath.addLine(to: CGPoint(x: rect.minX + 60, y: y))
        accentColor.withAlphaComponent(0.4).setStroke()
        linePath.lineWidth = 2
        linePath.lineCapStyle = .round
        linePath.stroke()
        y += 20

        return y
    }

    // MARK: - Project Header

    private func drawProjectHeader(
        _ name: String,
        at startY: CGFloat,
        in rect: CGRect,
        context: UIGraphicsPDFRendererContext,
        entryCount: Int
    ) -> CGFloat {
        var y = startY

        // Soft rounded bar in accent color
        let barRect = CGRect(x: rect.minX, y: y, width: rect.width, height: 34)
        accentColor.withAlphaComponent(0.12).setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 10).fill()

        // Left accent strip
        let stripRect = CGRect(x: rect.minX, y: y, width: 4, height: 34)
        accentColor.withAlphaComponent(0.6).setFill()
        UIBezierPath(roundedRect: stripRect, cornerRadius: 2).fill()

        let projectAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: textColor
        ]
        name.draw(at: CGPoint(x: rect.minX + 14, y: y + 7), withAttributes: projectAttrs)

        let countAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: secondaryTextColor
        ]
        let countText = "\(entryCount) reflections"
        let countSize = countText.size(withAttributes: countAttrs)
        countText.draw(at: CGPoint(x: rect.maxX - countSize.width - 12, y: y + 9), withAttributes: countAttrs)

        y += 48

        return y
    }

    // MARK: - Mood Chart

    private func drawMoodChart(
        moodPoints: [(date: Date, mood: String, value: Double)],
        at startY: CGFloat,
        in rect: CGRect,
        context: UIGraphicsPDFRendererContext
    ) -> CGFloat {
        var y = startY

        let chartTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: secondaryTextColor
        ]
        "How you felt".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: chartTitleAttrs)
        y += 24

        let chartHeight: CGFloat = 120
        let dateLabelAreaBelow: CGFloat = 16
        let chartLeft = rect.minX + 12
        let chartRight = rect.maxX - 12
        let chartWidth = chartRight - chartLeft
        let chartTop = y
        let chartBottom = chartTop + chartHeight

        // Soft background
        let bgRect = CGRect(x: chartLeft, y: chartTop, width: chartWidth, height: chartHeight)
        lightFillColor.setFill()
        UIBezierPath(roundedRect: bgRect, cornerRadius: 10).fill()

        // Light horizontal guides at 2 and 4 (no labels — just subtle lines)
        let chartPaddingY: CGFloat = 14
        for level in [2.0, 3.0, 4.0] {
            let yPos = yPositionForValue(CGFloat(level), chartTop: chartTop, chartBottom: chartBottom, padding: chartPaddingY)
            let guidePath = UIBezierPath()
            guidePath.move(to: CGPoint(x: chartLeft + 8, y: yPos))
            guidePath.addLine(to: CGPoint(x: chartRight - 8, y: yPos))
            UIColor(white: 0.90, alpha: 1.0).setStroke()
            guidePath.lineWidth = 0.5
            let pattern: [CGFloat] = [4, 4]
            guidePath.setLineDash(pattern, count: 2, phase: 0)
            guidePath.stroke()
        }

        guard !moodPoints.isEmpty else {
            return chartBottom + dateLabelAreaBelow + 10
        }

        // Calculate positions
        var pointPositions: [(x: CGFloat, y: CGFloat)] = []
        let chartPaddingX: CGFloat = 16
        let plotLeft = chartLeft + chartPaddingX
        let plotWidth = chartWidth - chartPaddingX * 2

        if moodPoints.count == 1 {
            let xPos = plotLeft + plotWidth / 2
            let yPos = yPositionForValue(CGFloat(moodPoints[0].value), chartTop: chartTop, chartBottom: chartBottom, padding: chartPaddingY)
            pointPositions.append((xPos, yPos))
        } else {
            let minDate = moodPoints.first!.date.timeIntervalSince1970
            let maxDate = moodPoints.last!.date.timeIntervalSince1970
            let dateSpan = max(maxDate - minDate, 1)

            for point in moodPoints {
                let xFraction = CGFloat((point.date.timeIntervalSince1970 - minDate) / dateSpan)
                let xPos = plotLeft + xFraction * plotWidth
                let yPos = yPositionForValue(CGFloat(point.value), chartTop: chartTop, chartBottom: chartBottom, padding: chartPaddingY)
                pointPositions.append((xPos, yPos))
            }
        }

        // Gradient fill under line
        if let cgContext = UIGraphicsGetCurrentContext(), pointPositions.count > 1 {
            cgContext.saveGState()

            let fillPath = UIBezierPath()
            fillPath.move(to: CGPoint(x: pointPositions.first!.x, y: chartBottom))
            for pos in pointPositions {
                fillPath.addLine(to: CGPoint(x: pos.x, y: pos.y))
            }
            fillPath.addLine(to: CGPoint(x: pointPositions.last!.x, y: chartBottom))
            fillPath.close()

            let clipPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 10)
            cgContext.addPath(clipPath.cgPath)
            cgContext.addPath(fillPath.cgPath)
            cgContext.clip(using: .winding)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                accentColor.withAlphaComponent(0.20).cgColor,
                accentColor.withAlphaComponent(0.02).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1]) {
                cgContext.drawLinearGradient(gradient,
                    start: CGPoint(x: chartLeft, y: chartTop),
                    end: CGPoint(x: chartLeft, y: chartBottom),
                    options: [])
            }

            cgContext.restoreGState()
        }

        // Line
        if pointPositions.count > 1 {
            let linePath = UIBezierPath()
            for (i, pos) in pointPositions.enumerated() {
                if i == 0 {
                    linePath.move(to: CGPoint(x: pos.x, y: pos.y))
                } else {
                    linePath.addLine(to: CGPoint(x: pos.x, y: pos.y))
                }
            }
            accentColor.withAlphaComponent(0.6).setStroke()
            linePath.lineWidth = 2.0
            linePath.lineJoinStyle = .round
            linePath.lineCapStyle = .round
            linePath.stroke()
        }

        // Dots — using the new watercolor mood palette
        for (i, point) in moodPoints.enumerated() {
            let pos = pointPositions[i]
            let dotRect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            moodUIColor(point.value).setFill()
            UIBezierPath(ovalIn: dotRect).fill()
        }

        // Mood labels — white pill background for contrast against the gradient
        let moodLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: UIColor(white: 0.25, alpha: 1.0)
        ]
        var drawnLabelRects: [CGRect] = []
        for (i, point) in moodPoints.enumerated() {
            let pos = pointPositions[i]
            let moodSize = point.mood.size(withAttributes: moodLabelAttrs)
            let pillRect = CGRect(
                x: pos.x - moodSize.width / 2 - 4,
                y: pos.y - 19,
                width: moodSize.width + 8,
                height: moodSize.height + 4
            )
            let overlaps = drawnLabelRects.contains { $0.intersects(pillRect) }
            if !overlaps {
                UIColor.white.withAlphaComponent(0.92).setFill()
                UIBezierPath(roundedRect: pillRect, cornerRadius: 4).fill()
                point.mood.draw(at: CGPoint(x: pos.x - moodSize.width / 2, y: pos.y - 17), withAttributes: moodLabelAttrs)
                drawnLabelRects.append(pillRect)
            }
        }

        // Date labels — darker for readability
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: UIColor(white: 0.35, alpha: 1.0)
        ]
        var dateIndices: [Int] = [0]
        if moodPoints.count > 1 { dateIndices.append(moodPoints.count - 1) }
        let desiredDateLabels = min(moodPoints.count, 5)
        if desiredDateLabels > 2 {
            let step = Double(moodPoints.count - 1) / Double(desiredDateLabels - 1)
            for j in 1..<(desiredDateLabels - 1) {
                dateIndices.append(Int(Double(j) * step))
            }
        }
        dateIndices = Array(Set(dateIndices)).sorted()

        var drawnDateRects: [CGRect] = []
        for i in dateIndices where i < pointPositions.count {
            let pos = pointPositions[i]
            let dateLabel = dateFormatter.string(from: moodPoints[i].date)
            let dateLabelSize = dateLabel.size(withAttributes: dateAttrs)
            let dateLabelRect = CGRect(
                x: pos.x - dateLabelSize.width / 2 - 2,
                y: chartBottom + 4,
                width: dateLabelSize.width + 4,
                height: dateLabelSize.height
            )
            let overlaps = drawnDateRects.contains { $0.intersects(dateLabelRect) }
            if !overlaps {
                dateLabel.draw(at: CGPoint(x: pos.x - dateLabelSize.width / 2, y: chartBottom + 4), withAttributes: dateAttrs)
                drawnDateRects.append(dateLabelRect)
            }
        }

        y = chartBottom + dateLabelAreaBelow + 10
        return y
    }

    private func yPositionForValue(_ value: CGFloat, chartTop: CGFloat, chartBottom: CGFloat, padding: CGFloat) -> CGFloat {
        let plotTop = chartTop + padding
        let plotBottom = chartBottom - padding
        let fraction = (value - 1.0) / 4.0
        return plotBottom - fraction * (plotBottom - plotTop)
    }

    /// Watercolor mood palette matching the in-app colors.
    private func moodUIColor(_ value: Double) -> UIColor {
        switch value {
        case 4.5...5: return UIColor(red: 0.55, green: 0.82, blue: 0.72, alpha: 1.0) // fresh mint
        case 3.5..<4.5: return UIColor(red: 0.58, green: 0.78, blue: 0.85, alpha: 1.0) // sky blue
        case 2.5..<3.5: return UIColor(red: 0.76, green: 0.78, blue: 0.66, alpha: 1.0) // soft olive
        case 1.5..<2.5: return UIColor(red: 0.85, green: 0.76, blue: 0.65, alpha: 1.0) // warm peach
        default:        return UIColor(red: 0.84, green: 0.68, blue: 0.72, alpha: 1.0) // blush pink
        }
    }

    // MARK: - Entry Drawing

    private func drawEntry(
        _ entry: VoiceEntry,
        at startY: CGFloat,
        in rect: CGRect,
        context: UIGraphicsPDFRendererContext,
        projects: [Project]
    ) -> CGFloat {
        var y = startY

        // Soft separator
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: rect.minX, y: y))
        linePath.addLine(to: CGPoint(x: rect.maxX, y: y))
        separatorColor.setStroke()
        linePath.lineWidth = 0.5
        linePath.stroke()
        y += 14

        let headingAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: textColor
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: textColor
        ]
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor(red: 0.25, green: 0.42, blue: 0.38, alpha: 1.0) // darker sage for print
        ]
        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: secondaryTextColor
        ]

        // Entry title (no numbering)
        let titleText = entry.summaryTitle.isEmpty ? "Untitled Entry" : entry.summaryTitle
        titleText.draw(at: CGPoint(x: rect.minX, y: y), withAttributes: headingAttrs)
        y += 20

        // Date + duration + mood
        var metaParts: [String] = [dateTimeString(entry.createdAt), formattedDuration(entry.durationSeconds)]
        if let mood = entry.mood { metaParts.append(mood) }
        if let pid = entry.projectId, let project = projects.first(where: { $0.id == pid }) {
            metaParts.append(project.name)
        }
        let metaLine = metaParts.joined(separator: "  ·  ")
        metaLine.draw(at: CGPoint(x: rect.minX, y: y), withAttributes: metaAttrs)
        y += 16

        // Tags
        if !entry.tags.isEmpty {
            let tagsLine = entry.tags.joined(separator: "  ·  ")
            tagsLine.draw(at: CGPoint(x: rect.minX, y: y), withAttributes: metaAttrs)
            y += 16
        }

        y += 6

        // Transcript
        "Transcript".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: labelAttrs)
        y += 16
        y = drawWrappedText(entry.transcript, at: y, in: rect, attributes: bodyAttrs, context: context)
        y += 10

        // Summary
        if !entry.summaryText.isEmpty {
            "Summary".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: labelAttrs)
            y += 16
            y = drawWrappedText(entry.summaryText, at: y, in: rect, attributes: [
                .font: UIFont.italicSystemFont(ofSize: 11),
                .foregroundColor: secondaryTextColor
            ], context: context)
            y += 10
        }

        // Action items
        if !entry.actionItems.isEmpty {
            "Action Items".draw(at: CGPoint(x: rect.minX, y: y), withAttributes: labelAttrs)
            y += 16
            for item in entry.actionItems {
                let bullet = "  ·  \(item)"
                bullet.draw(at: CGPoint(x: rect.minX, y: y), withAttributes: bodyAttrs)
                y += 16
            }
        }

        return y
    }

    private func drawWrappedText(
        _ text: String,
        at startY: CGFloat,
        in rect: CGRect,
        attributes: [NSAttributedString.Key: Any],
        context: UIGraphicsPDFRendererContext
    ) -> CGFloat {
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )

        var y = startY

        if y + boundingRect.height > rect.maxY {
            let availableRect = CGRect(x: rect.minX, y: y, width: rect.width, height: rect.maxY - y)
            attributedString.draw(with: availableRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

            context.beginPage()
            y = rect.minY
            let newRect = CGRect(x: rect.minX, y: y, width: rect.width, height: rect.maxY - y)
            attributedString.draw(with: newRect, options: [.usesLineFragmentOrigin], context: nil)
            y += boundingRect.height
        } else {
            let textRect = CGRect(x: rect.minX, y: y, width: rect.width, height: boundingRect.height)
            attributedString.draw(with: textRect, options: [.usesLineFragmentOrigin], context: nil)
            y += boundingRect.height
        }

        return y
    }

    private func estimateEntryHeight(_ entry: VoiceEntry) -> CGFloat {
        var height: CGFloat = 80
        height += CGFloat(entry.transcript.count / 80) * 14
        height += CGFloat(entry.summaryText.count / 80) * 14
        height += CGFloat(entry.actionItems.count) * 16
        return max(height, 120)
    }

    // MARK: - Formatting

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func dateTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
