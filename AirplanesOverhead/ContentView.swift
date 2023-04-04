import SwiftUI
import CoreLocation
import Alamofire
import SwiftyJSON
import AVFoundation

struct Flight: Codable, Identifiable {
    let id: UUID = UUID()
    let ident: String?
    let fa_flight_id: String?
    let actual_off: String?
    let actual_on: String?
    let origin: Airport?
    let destination: Airport?
    let last_position: Position?
    let aircraft_type: String?

    struct Airport: Codable {
        let code: String?
        let code_icao: String?
        let code_iata: String?
        let code_lid: String?
        let timezone: String?
        let name: String?
        let city: String?
        let airport_info_url: String?
    }

    struct Position: Codable {
        let fa_flight_id: String?
        let altitude: Int?
        let altitude_change: String?
        let groundspeed: Int?
        let heading: Int?
        let latitude: Double?
        let longitude: Double?
        let timestamp: String?
        let update_type: String?
    }
    
    var originDescription: String {
        if let origin = self.origin {
            return origin.name ?? "Unknown airport"
        } else {
            return "Unknown origin"
        }
    }
    
    var destinationDescription: String {
        if let destination = self.destination {
            return destination.name ?? "Unknown airport"
        } else {
            return "Unknown destination"
        }
    }
}

struct FlightResponse: Decodable {
    let flights: [Flight]
}

struct ContentView: View {
    @State private var locationManager = CLLocationManager()
    @State private var aircraftData: [Flight] = []
    @State private var aircraftTypeLookup: [String: String]
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var stopSpeakingButton = false
    private let flightAwareAPIKey: String
    private let searchRadiusOptions = [1.0, 5.0, 10.0, 50.0]
    @State private var searchRadius = 5.0
    @State private var loading = false
    
    init() {
        guard let apiKey = Bundle.main.infoDictionary?["FlightAwareAPIKey"] as? String else {
            fatalError("FlightAware API key not found.")
        }
        self.flightAwareAPIKey = apiKey
        let manufacturersLookup = Self.loadManufacturersLookup(from: "manufacturers")
        let lookup = Self.loadAircraftTypeLookup(from: "aircraft-types", usingManufacturers: manufacturersLookup)
        _aircraftTypeLookup = State(initialValue: lookup)
    }
    
    var body: some View {
        VStack {
            Text("Tap to find aircraft flying nearby")
                .padding()
            Picker("Search Radius", selection: $searchRadius) {
                ForEach(searchRadiusOptions, id: \.self) { radius in
                    Text("\(Int(radius)) miles")
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            Button(action: {
                if let location = locationManager.location {
                    loading = true
                    fetchAircraftData(location: location, radius: searchRadius / 69.0) { aircraftData in
                        self.aircraftData = aircraftData
                        speakAircraftData()
                        loading = false
                    }
                }
            }) {
                Image(systemName: "airplane")
                    .font(.system(size: 72))
            }
            .padding()
            if loading {
                Text("Loading...")
            } else if aircraftData.isEmpty {
                Text("No flights found.")
            } else {
                List(aircraftData) { flight in
                    if let aircraftType = aircraftTypeLookup[flight.aircraft_type ?? ""] {
                        let flightLevel = flight.last_position?.altitude ?? 0
                        let groundspeed = flight.last_position?.groundspeed ?? 0
                        let origin = flight.origin?.name ?? "Unknown origin"
                        let destination = flight.destination?.name ?? "Unknown destination"
                        Text("\(aircraftType) - Flight level \(flightLevel / 100), Speed \(groundspeed) knots, Origin \(origin), Destination \(destination)")
                    } else {
                        Text("Unknown aircraft")
                    }
                }
            }
            Button(action: {
                stopSpeakingButton = true
            }) {
                Text("Stop Speaking")
            }
        }
        .onAppear {
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        }
    }

    func fetchAircraftData(location: CLLocation, radius: Double, completion: @escaping ([Flight]) -> Void) {
        let baseURL = "https://aeroapi.flightaware.com/aeroapi/flights/search"
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let query = "-latlong \"\(lat - radius) \(lon - radius) \(lat + radius) \(lon + radius)\""

        let parameters: [String: Any] = [
            "query": query
        ]

        let headers: HTTPHeaders = [
            "x-apikey": self.flightAwareAPIKey
        ]

        AF.request(baseURL, method: .get, parameters: parameters, headers: headers).responseDecodable(of: FlightResponse.self) { response in
            switch response.result {
            case .success(let flightResponse):
                DispatchQueue.main.async {
                    if flightResponse.flights.isEmpty {
                        self.aircraftData = []
                    } else {
                        completion(flightResponse.flights)
                    }
                    self.loading = false
                }
            case .failure(let error):
                print("Error fetching aircraft data:", error)
            }
        }
    }
    
    func speakAircraftData() {
        stopSpeakingButton = false
        DispatchQueue.global(qos: .userInitiated).async {
            for flight in aircraftData {
                if let aircraftType = aircraftTypeLookup[flight.aircraft_type ?? ""] {
                    let originDescription = flight.originDescription
                    let destinationDescription = flight.destinationDescription
                    let flightLevel = flight.last_position?.altitude ?? 0
                    let groundspeed = flight.last_position?.groundspeed ?? 0
                    
                    let speechText = "There is a \(aircraftType) flying at flight level \(flightLevel / 100) and a speed of \(groundspeed) knots. Originating from \(originDescription) and flying to \(destinationDescription)."
                    let utterance = AVSpeechUtterance(string: speechText)
                    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                    speechSynthesizer.speak(utterance)
                    while speechSynthesizer.isSpeaking {
                        if stopSpeakingButton {
                            speechSynthesizer.stopSpeaking(at: .immediate)
                            break
                        }
                        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
                    }
                }
            }
            stopSpeakingButton = false
        }
    }
    
    static func loadManufacturersLookup(from filename: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            print("JSON file not found.")
            return [:]
        }

        var manufacturersLookup: [String: String] = [:]

        do {
            let data = try Data(contentsOf: url)
            let json = try JSON(data: data)

            for (_, subJson) in json {
                let id = subJson["id"].stringValue
                let name = subJson["name"].stringValue
                manufacturersLookup[id] = name
            }
        } catch let error {
            print("Error reading JSON file: \(error)")
        }

        return manufacturersLookup
    }
    
    static func loadAircraftTypeLookup(from filename: String, usingManufacturers manufacturers: [String: String]) -> [String: String] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            print("JSON file not found.")
            return [:]
        }

        var aircraftTypeLookup: [String: String] = [:]

        do {
            let data = try Data(contentsOf: url)
            let json = try JSON(data: data)

            for (_, subJson) in json {
                let typeCode = subJson["icaoCode"].stringValue
                let manufacturerId = subJson["manufacturer"].stringValue
                let manufacturerName = manufacturers[manufacturerId] ?? ""
                let fullName = manufacturerName + " " + subJson["name"].stringValue
                aircraftTypeLookup[typeCode] = fullName
            }
        } catch let error {
            print("Error reading JSON file: \(error)")
        }

        return aircraftTypeLookup
    }
}
