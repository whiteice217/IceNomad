//
//  LoadingMessages.swift
//  IceNomad
//
//  Created by Bryan Stern on 7/6/26.
//
import Foundation

struct LoadingMessages {

    static let messages = [
        "Stealing spare wires from the old ice castle...",
        "Finding out who unplugged the magic antenna...",
        "Building a radio from mysterious leftovers...",
        "Checking if this thing is supposed to spark...",
        "Probably should not have touched that crystal...",
        "Teaching an iceberg how to hold a signal...",
        "Installing the first penguin-built antenna...",
        "Searching for friends who appreciate weird radio projects...",
        "Making a tower out of snow, scrap, and determination...",
        "Finding a screwdriver that isn't frozen...",
        "Negotiating with the antenna goblins...",
        "Removing unnecessary ice from the circuitry...",
        "Giving the radio a tiny penguin hat...",
        "Checking if the wires are connected to the right snowbank...",
        "Adding more antenna. That always works.",
        "Making the signal taller than the iceberg...",
        "Testing the emergency fish-powered generator...",
        "Borrowing batteries from suspiciously abandoned machines...",
        "Checking if the antenna still believes in itself...",
        "Teaching the radio to scream into the void politely...",
        "Looking for friendly voices in the frozen silence...",
        "Sending a tiny penguin hello...",
        "Waiting for someone to answer the tiny penguin hello...",
        "Adjusting the friendship frequency...",
        "Searching for lost companions across the ice...",
        "Finding other strange creatures on the network...",
        "Building bridges between lonely icebergs...",
        "Creating a home away from home...",
        "Packing snacks for the long network journey...",
        "Making sure nobody stole the fish supply...",
        "Checking the emergency fish protocol...",
        "Deploying maximum penguin engineering...",
        "Activating questionable but clever solutions...",
        "Replacing broken parts with slightly less broken parts...",
        "Applying advanced penguin logic...",
        "Turning it off and turning it back on...",
        "Giving the antenna a gentle motivational speech...",
        "Threatening the antenna with retirement...",
        "The antenna has reconsidered its choices...",
        "Checking why the packets wandered away...",
        "Following lost packets through the snow...",
        "Finding packets hiding under ice chunks...",
        "Rescuing trapped messages...",
        "Convincing TCP to stop being dramatic...",
        "Waiting patiently for ACK...",
        "Wondering where the SYN packets went...",
        "Searching the frozen wilderness for missing handshakes...",
        "Finding the node that forgot to introduce itself...",
        "Politely knocking on distant nodes...",
        "Checking if the mesh remembered us...",
        "Teaching LoRa how to whisper farther...",
        "Making tiny radio waves do tiny miracles...",
        "Adjusting the antenna because physics said no...",
        "Moving the antenna three inches because that fixes everything...",
        "Rotating the antenna until the penguin feels confident...",
        "Checking if the frequency is actually the frequency...",
        "Making sure 915 MHz is still where we left it...",
        "Calibrating the magic ice radio...",
        "Cleaning snow off the RNode...",
        "Giving the Heltec a tiny winter jacket...",
        "Making sure USB cables are not haunted...",
        "Looking for the mysterious missing serial port...",
        "Finding out why the computer doesn't see the radio...",
        "Checking permissions in the frozen terminal...",
        "Asking Linux nicely for access...",
        "Negotiating with /dev/ttyUSB0...",
        "Searching the logs for suspicious snowflakes...",
        "Reading ancient messages from dmesg...",
        "Looking through the filesystem cave...",
        "Checking the frozen configuration scrolls...",
        "Finding the misplaced identity file...",
        "Searching ~/.reticulum for clues...",
        "Looking through NomadNet footprints...",
        "Recovering lost network memories...",
        "Making sure the cryptographic penguin passport works...",
        "Polishing the identity key...",
        "Generating fresh frozen randomness...",
        "Creating a new digital flipperprint...",
        "Protecting the penguin's secret diary...",
        "Locking the icebox of encryption...",
        "Checking if the firewall is feeling friendly...",
        "Opening a safe tunnel through the snowstorm...",
        "Building a cozy encrypted igloo...",
        "Connecting the lonely nodes together...",
        "Finding other wanderers...",
        "Broadcasting the penguin beacon...",
        "Waiting for another weird penguin to answer...",
        "Listening for distant squawks on the radio...",
        "Translating mysterious ice noises...",
        "Determining if that was a signal or just a seal...",
        "Checking network weather...",
        "Watching packet snow fall...",
        "Predicting tomorrow's connectivity forecast...",
        "Clearing the RF blizzard...",
        "Finding a quiet spot on the spectrum...",
        "Searching the frozen electromagnetic ocean...",
        "Mapping invisible radio rivers...",
        "Charting unknown network waters...",
        "Exploring places nobody bothered to connect...",
        "Leaving little digital footprints behind...",
        "Making a trail through the mesh...",
        "Following the wandering signal...",
        "Creating a path where there wasn't one before...",
        "Building a tiny internet in the snow...",
        "Opening the penguin command center...",
        "Starting the slightly questionable expedition...",
        "Preparing the backpack full of wires...",
        "Checking the emergency snacks...",
        "Charging the friendship machine...",
        "Almost ready to wander...",
        "The antenna is awake...",
        "The ice is listening...",
        "The network is responding...",
        "Someone answered the penguin...",
        "A new friend has been discovered...",
        "The frozen frontier is connected...",
        "Day 37: The antenna still works somehow...",
        "The penguin has made another questionable invention...",
        "The penguin insists this is a feature...",
        "The penguin denies breaking anything...",
        "The penguin has fixed the problem by adding more wires...",
        "The penguin has consulted the ancient troubleshooting scrolls...",
        "The penguin has tried turning the iceberg off and on again...",
        "The penguin is pretty sure this is networking...",
        "The penguin understands approximately 63% of this problem...",
        "The penguin has declared victory over the error message...",
        "The penguin has defeated the mysterious red light...",
        "The penguin has made friends with the blinking LED..."
    ]

// Keeps track of the last message shown

        private static var lastMessage: String?

        static func random() -> String {

            var newMessage: String

            repeat {

                newMessage = messages.randomElement() ?? "Loading..."

            } while newMessage == lastMessage

            lastMessage = newMessage

            return newMessage

        }

    }
