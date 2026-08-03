//
//  LoadingMessages.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//
//  Each array corresponds to a real startup stage in StartupManager —
//  not just decorative flavor text on a timer. See StartupManager for
//  what actually gates each stage's completion.
//
import Foundation

struct LoadingMessages {

    static let softwareLaunching = [
        "IceNomad is waking from its frozen slumber…",
        "Warming up the expedition core…",
        "Breaking through the startup ice…",
        "Penguin navigator is preparing for departure…",
        "Initializing the frozen frontier systems…",
        "Snow is clearing from the communication console…",
        "The IceNomad explorer is stretching its flippers…",
        "Activating the glacier command center…",
        "Loading expedition tools from the ice shelf…",
        "Preparing the penguin colony interface…",
        "The northern systems are coming online…",
        "IceNomad is preparing to explore the unknown…",
        "Booting the colony navigation systems…",
        "Frozen circuits are beginning to thaw…",
        "Gathering supplies for the digital expedition…",
        "The explorer's pack is being loaded…",
        "Setting up the IceNomad command post…",
        "Clearing the frost from system pathways…",
        "Penguin crew is reporting for duty…",
        "The ice engine is roaring to life…"
    ]

    static let foundConnections = [
        "Scout penguin discovered nearby communication trails…",
        "Frozen pathways detected across the horizon…",
        "Ice bridges have been spotted in the distance…",
        "Network footprints found in fresh snow…",
        "Expedition routes have been mapped…",
        "Nearby colonies have been located…",
        "The scout team has returned with connection data…",
        "Signals detected beyond the frozen ridge…",
        "Discovering paths through the digital glacier…",
        "Penguin scouts found friendly routes…",
        "New trails are appearing on the ice map…",
        "The communication tundra is revealing its secrets…",
        "Colony signals detected nearby…",
        "Ice routes identified and marked…",
        "The explorer compass has found new directions…",
        "Following digital footprints across the snow…",
        "Network landmarks discovered…",
        "Frozen pathways are available for travel…",
        "The colony map is expanding…",
        "New communication glaciers discovered…"
    ]

    static let connectingToNetwork = [
        "Penguin scout is waddling toward the Reticulum network…",
        "Attempting to cross the frozen communication tundra…",
        "Carving a secure ice bridge to the network…",
        "Sending a beacon across the frozen horizon…",
        "Searching for a friendly colony connection…",
        "Beginning the journey across the digital glacier…",
        "Throwing a signal flare into the snowy wilderness…",
        "The explorer is knocking on the frozen network door…",
        "Building a pathway through the ice fields…",
        "Broadcasting a call across the polar winds…",
        "Looking for nearby penguin colonies…",
        "Crossing the digital mountain pass…",
        "Attempting to reach the frozen meshlands…",
        "Scout unit is navigating the icy channels…",
        "Establishing a route through the glacier network…",
        "Launching a connection probe into the snowstorm…",
        "Searching for Reticulum footprints…",
        "Opening a tunnel through the frozen frontier…",
        "Sending an expedition request into the wild…",
        "Penguin messenger is traveling across the ice…"
    ]

    static let connectionEstablished = [
        "Penguin colony link established!",
        "The ice bridge has been successfully formed…",
        "Secure communication tunnel carved through the glacier…",
        "IceNomad has reached the frozen frontier…",
        "The expedition route is now open…",
        "Connected to the frozen meshlands…",
        "Scout has returned with good news!",
        "Signal strength is stable across the ice…",
        "The glacier gateway is unlocked…",
        "Communication winds are flowing smoothly…",
        "A new path through the snow has opened…",
        "Reticulum handshake completed successfully…",
        "The colony is connected and ready…",
        "Frozen channels are now active…",
        "The ice tunnel has been secured…",
        "Expedition communications are online…",
        "Digital footprints confirmed…",
        "The frozen network welcomes IceNomad…",
        "The penguin fleet has joined the mesh…",
        "Connection crystallized successfully…",
        "The bridge between ice worlds is complete…"
    ]

    static let receivingAnnounces = [
        "Listening for penguin scouts across the ice…",
        "Gathering whispers from distant glaciers…",
        "Collecting announcements from frozen territories…",
        "Detecting fresh footprints in the snow…",
        "Mapping nearby explorers across the tundra…",
        "Scanning the horizon for friendly signals…",
        "The colony radio is listening…",
        "Receiving messages carried by the polar winds…",
        "Updating the IceNomad explorer map…",
        "New travelers are appearing on the ice sheet…",
        "Tracking distant signals beyond the mountains…",
        "Learning about nearby frozen outposts…",
        "Penguin scouts are reporting home…",
        "Listening for voices across the glacier…",
        "Gathering node sightings from the wilderness…",
        "Following communication trails through the snow…",
        "Monitoring the frozen airwaves…",
        "Expanding the expedition map…",
        "Discovering new members of the colony…",
        "Recording signals from the frozen frontier…"
    ]

    static let preloadingTux = [
        "Tux the search penguin is fetching the map…",
        "Charting the mesh with Tux's spyglass…",
        "Tux is waddling ahead to scout the index…",
        "Warming up the search burrow…",
        "Tux is flipping through the frozen card catalog…",
        "Fetching the colony's search post…",
        "Tux is diving for the latest index…",
        "Stocking the search burrow with fresh listings…",
        "Tux is tracking down the mesh directory…",
        "Preloading Tux so the search bar is ready to go…"
    ]

    static let appReady = [
        "IceNomad is ready for exploration!",
        "The frozen frontier awaits your journey…",
        "All ice bridges are stable and operational…",
        "Expedition systems are fully online…",
        "Welcome back, explorer. The colony awaits…",
        "IceNomad has thawed and is ready to roam…",
        "The penguin crew is ready for adventure…",
        "Navigation systems are locked and loaded…",
        "The glacier gates are open…",
        "Your journey across the mesh begins now…",
        "The snow trails are waiting…",
        "IceNomad is connected to the world beyond…",
        "Explorer mode activated…",
        "The frozen wilderness is yours to discover…",
        "Communication crystals are glowing…",
        "The northern network is standing by…",
        "Your expedition pack is complete…",
        "Signals are clear. The colony is online…",
        "IceNomad has officially taken flight…",
        "Welcome to the endless frozen frontier…",
        "Adventure awaits beyond the next snow ridge…"
    ]

    // Keeps track of the last message shown, so consecutive picks never repeat.
    private static var lastMessage: String?

    static func random(from pool: [String]) -> String {

        var newMessage: String

        repeat {

            newMessage = pool.randomElement() ?? "Loading…"

        } while newMessage == lastMessage && pool.count > 1

        lastMessage = newMessage

        return newMessage
    }
}
