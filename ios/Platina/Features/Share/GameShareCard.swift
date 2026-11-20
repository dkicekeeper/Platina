import SwiftUI
import UIKit
import DesignTokens
import DesignComponents
import PSNKit
import PlatinaStore

/// A game's progress as a picture for Stories or a chat (docs/PLAN.md §3.5): the platinum, or
/// how far along the road it is.
struct GameShareSheet: View {
    let game: GameRecord

    var body: some View {
        let model = GameShareModel(game: game)
        ShareCardSheet(
            previewTitle: game.name,
            load: { await model.loadingIcon() },
            message: { $0.message },
            card: { model, format in GameShareCard(model: model, format: format) }
        )
    }
}

@MainActor
struct GameShareModel {
    let name: String
    let progress: Int
    let isPlatinum: Bool
    let earned: TrophyCounts
    let defined: TrophyCounts
    let hours: Int?
    let iconURL: URL?
    var icon: UIImage?

    init(game: GameRecord) {
        name = game.name
        progress = game.progress
        isPlatinum = game.isPlatinumEarned
        earned = game.earned
        defined = game.defined
        hours = game.playSeconds.map { Int($0 / 3600) }
        iconURL = game.iconURL
    }

    /// The card with the game's icon downloaded (a share picture is drawn offline).
    func loadingIcon() async -> GameShareModel? {
        var copy = self
        if let iconURL, let result = try? await URLSession.shared.data(from: iconURL) {
            copy.icon = UIImage(data: result.0)
        }
        return copy
    }

    var message: String {
        isPlatinum
            ? String(localized: "share.message.platinum \(name)")
            : String(localized: "share.message.progress \(name) \(progress)")
    }
}

private struct GameShareCard: View {
    let model: GameShareModel
    let format: ShareCard.Format

    var body: some View {
        ShareCardFrame(format: format, brand: "Platina") {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if let icon = model.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(.rect(cornerRadius: AppRadius.xl))
                }
                Text(verbatim: model.isPlatinum ? String(localized: "share.card.platinum") : "\(model.progress)%")
                    .font(AppTypography.h1)
                    .foregroundStyle(model.isPlatinum ? TrophyType.platinum.color : AppColors.Text.primaryOnDark)
                Text(verbatim: model.name)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.Text.primaryOnDark)
                HStack(spacing: AppSpacing.md) {
                    ForEach(TrophyType.allCases.filter { model.defined[$0] > 0 }, id: \.self) { type in
                        Label {
                            Text(verbatim: "\(model.earned[type])/\(model.defined[type])")
                        } icon: {
                            Image(systemName: type.systemImage).foregroundStyle(type.color)
                        }
                    }
                }
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.Text.primaryOnDark)
                if let hours = model.hours, hours > 0 {
                    Text("share.card.hours \(hours)")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.Text.secondaryOnDark)
                }
            }
        }
    }
}
