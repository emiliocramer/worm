import SwiftUI

/// Navigation routes for each node in the personality graph.
enum NodeRoute: Hashable, Codable {
    case profile
    case profileChat
    case graph
    case digging
    case spotify
    case appleMusic
    case youtube
    case contacts
    case photos
    case calendar
    case selfie
}

/// A node as drawn in the graph.
private struct GraphNode: Identifiable {
    let id: NodeRoute
    let title: String
    let isConnected: Bool
    var position: CGPoint = .zero

    var route: NodeRoute { id }
}

/// A simple node graph. A central node sits in the middle with each data node
/// arranged around it as a tappable satellite.
struct PersonalityGraphView: View {
    @Environment(SpotifyMusicNode.self) private var spotify
    @Environment(AppleMusicNode.self) private var appleMusic
    @Environment(YouTubeCultureNode.self) private var youtube
    @Environment(ContactsNode.self) private var contacts
    @Environment(PhotosNode.self) private var photos
    @Environment(CalendarNode.self) private var calendar
    @Environment(SelfieNode.self) private var selfie
    @Environment(\.dismiss) private var dismiss

    private let centerDotSize: CGFloat = 108
    private let nodeDotSize: CGFloat = 92

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = min(geo.size.width, geo.size.height) * 0.31
                let nodes = layoutNodes(
                    center: center,
                    radius: radius,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )

                ZStack {
                    ForEach(nodes) { node in
                        Path { path in
                            path.move(to: center)
                            path.addLine(to: node.position)
                        }
                        .stroke(
                            .white.opacity(0.14),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round)
                        )
                    }

                    centerNode
                        .position(center)

                    ForEach(nodes) { node in
                        NavigationLink(value: node.route) {
                            nodeBubble(node, labelIsBelow: node.position.y >= center.y)
                        }
                        .buttonStyle(.plain)
                        .position(node.position)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(Color(white: 0.035).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .liquidGlass(in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Nodes

    private var nodeList: [GraphNode] {
        [
            GraphNode(
                id: .spotify,
                title: "Spotify",
                isConnected: spotify.isAuthorized
            ),
            GraphNode(
                id: .appleMusic,
                title: "Apple Music",
                isConnected: appleMusic.isAuthorized
            ),
            GraphNode(
                id: .youtube,
                title: "YouTube",
                isConnected: youtube.isAuthorized
            ),
            GraphNode(
                id: .contacts,
                title: "Contacts",
                isConnected: contacts.isAuthorized
            ),
            GraphNode(
                id: .photos,
                title: "Photos",
                isConnected: photos.isAuthorized
            ),
            GraphNode(
                id: .calendar,
                title: "Calendar",
                isConnected: calendar.isAuthorized
            ),
            GraphNode(
                id: .selfie,
                title: "Selfie",
                isConnected: selfie.isAuthorized
            ),
        ]
    }

    private func layoutNodes(center: CGPoint, radius: CGFloat, time: TimeInterval) -> [GraphNode] {
        var nodes = nodeList
        let count = nodes.count
        guard count > 0 else { return nodes }

        for index in nodes.indices {
            let angle = (.pi * 2 * Double(index) / Double(count)) - (.pi / 2)
            let phase = (time * 0.22) + (Double(index) * 1.7)
            let activeRadius = radius + (CGFloat(sin(phase * 0.7)) * 6)

            nodes[index].position = CGPoint(
                x: center.x + (activeRadius * CGFloat(cos(angle))) + (CGFloat(cos(phase)) * 7),
                y: center.y + (activeRadius * CGFloat(sin(angle))) + (CGFloat(sin(phase * 0.9)) * 7)
            )
        }
        return nodes
    }

    private var centerNode: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.96))
                .frame(width: centerDotSize, height: centerDotSize)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)

            Text("You")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.black.opacity(0.78))
        }
        .frame(width: 144, height: 144)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You")
    }

    private func nodeBubble(_ node: GraphNode, labelIsBelow: Bool) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(node.isConnected ? 0.94 : 0.74))
                .frame(width: nodeDotSize, height: nodeDotSize)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(node.isConnected ? 0.0 : 0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 14, y: 8)

            nodeLabel(node)
                .offset(y: labelIsBelow ? 62 : -62)
        }
        .frame(width: 168, height: 168)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.title), \(node.isConnected ? "connected" : "not connected")")
    }

    private func nodeLabel(_ node: GraphNode) -> some View {
        Text(node.title)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.88))
        .multilineTextAlignment(.center)
    }
}

#Preview {
    NavigationStack {
        PersonalityGraphView()
    }
    .environment(SpotifyMusicNode())
    .environment(AppleMusicNode())
    .environment(YouTubeCultureNode())
    .environment(ContactsNode())
    .environment(PhotosNode())
    .environment(CalendarNode())
    .environment(SelfieNode())
}
