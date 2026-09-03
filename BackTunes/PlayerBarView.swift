import SwiftUI

/// The persistent player overlay: a mini bar above the tab bar, expandable
/// into a full-screen player. The webview is always mounted in this overlay —
/// when collapsed it slides offscreen so playback keeps running.
struct PlayerOverlayView: View {
    let video: Video
    @Binding var expanded: Bool
    let screenHeight: CGFloat

    @EnvironmentObject private var player: PlayerModel

    var body: some View {
        GeometryReader { geo in
            let embedHeight = geo.size.width * 9 / 16

            ZStack(alignment: .top) {
                // The video surface. Slides offscreen when collapsed, but the
                // webview itself stays alive so audio never stops.
                PlayerWebView(video: video)
                    .frame(width: geo.size.width, height: embedHeight)
                    .offset(y: expanded ? 0 : -(embedHeight + 120))
                    .accessibilityHidden(!expanded)

                if expanded {
                    PlayerControlsView(video: video, topInset: embedHeight, expanded: $expanded)
                        .background(.background.ignoresSafeArea())
                } else {
                    MiniPlayerBar(video: video)
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                // Mini-bar backdrop.
                expanded ? Color.clear : AnyShapeStyle(.bar.ignoresSafeArea())
            )
        }
        .frame(height: expanded ? screenHeight : 60)
        .overlay(alignment: .top) {
            if !expanded { MiniProgressBar() }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { withAnimation(.easeOut(duration: 0.25)) { expanded = true } } }
    }
}

// MARK: - Mini bar

private struct MiniProgressBar: View {
    @EnvironmentObject private var player: PlayerModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: progressWidth(total: geo.size.width))
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 0)
    }

    private func progressWidth(total: CGFloat) -> CGFloat {
        guard player.duration > 0 else { return 0 }
        return total * min(1, max(0, player.elapsed / player.duration))
    }
}

private struct MiniPlayerBar: View {
    let video: Video

    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: video.thumbnailURL)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.leading, 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.title.isEmpty ? video.title : player.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Text(player.channel.isEmpty ? video.channel : player.channel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)

            Button {
                player.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .frame(height: 57)
    }
}

// MARK: - Expanded controls

private struct PlayerControlsView: View {
    let video: Video
    let topInset: CGFloat

    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @Binding var expanded: Bool
    @State private var dragValue: Double?

    var body: some View {
        VStack(spacing: 0) {
            // Header row.
            HStack {
                Button {
                    withAnimation(.easeIn(duration: 0.2)) { expanded = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    library.toggleBookmark(video)
                } label: {
                    Image(systemName: library.isBookmarked(video) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)

                Button {
                    player.stop()
                    withAnimation { expanded = false }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 4) {
                if player.isAd {
                    Text("Ad · skipping…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text(player.title.isEmpty ? video.title : player.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(player.channel.isEmpty ? video.channel : player.channel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            Spacer(minLength: 12)

            // Scrubber.
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { dragValue ?? player.elapsed },
                        set: { newValue in
                            dragValue = newValue
                            player.elapsed = newValue
                        }
                    ),
                    in: 0...max(player.duration, 1)
                ) { editing in
                    if editing {
                        player.beginScrubbing()
                    } else if let value = dragValue {
                        player.seek(to: value)
                        player.endScrubbing()
                        dragValue = nil
                    }
                }
                .tint(.accentColor)

                HStack {
                    Text(timeString(player.elapsed))
                    Spacer()
                    Text(timeString(player.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            // Transport controls.
            HStack(spacing: 36) {
                Button {
                    player.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                .buttonStyle(.plain)

                Button {
                    player.skipForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

            Spacer(minLength: 16)
        }
        .padding(.top, topInset)
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
