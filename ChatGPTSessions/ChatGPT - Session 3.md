`2023-04-11 10:07:24`

_Prompt_: 
I have an iOS app called AirplanesOverhead that you helped create for me. It looks up the current aircraft flying overhead using the FlightAware API and then announces information about each aircraft. I would like some help in making changes. Here is the current source code for the iOS app. It uses SwiftUI and this is the ContentView.swift file contents: import SwiftUI
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


To make changes to your existing iOS app, you can follow these steps:

1. Create a separate file for the Flight and related structs. This will improve code organization and make it easier to maintain your code. Create a new file called Flight.swift and move the Flight, Airport, and Position structs into it.
2. Update the app to allow users to choose between different units for speed and altitude. You can add a Picker with the options "knots" and "km/h" for speed, and "feet" and "meters" for altitude. Then, update the text and speech accordingly, using a helper function to convert the values as needed.

Here's an example of how to update your ContentView.swift file to implement these changes:

```swift
// Add these properties inside the ContentView struct
@State private var speedUnit: SpeedUnit
```

_Prompt_: 
Actually I would like to add a new option to switch to a different data source for the live aircraft data. This other source is to directly access the Piaware device I have installed on my local network. It gathers only flight information form the ADS-B receiver and has a different format. I am not sure what type of API it exposes.

To switch between different data sources, you can implement a separate function to fetch data from your Piaware device, and then add a Picker to allow users to choose between the FlightAware API and the local Piaware device as data sources. To do this, you'll need to:

1. Discover the API endpoint and format provided by your local Piaware device. You can usually find this information in the device's documentation or by accessing its web interface.
2. Create a new function, e.g., fetchAircraftDataFromPiaware, that fetches the aircraft data from your local Piaware device. Make sure to parse the data into the existing Flight struct or create a new struct if the format is very different.
3. Add a Picker to the UI to allow users to choose between the FlightAware API and the local Piaware device as data sources. Update the button's action to fetch data from the selected source.

Here's an example of how you might modify your ContentView.swift file:

```swift
// Add a new enum and property inside the ContentView struct
enum DataSource {
    case flightAwareAPI
    case localPiaware
}

@State private var dataSource: DataSource = .flightAwareAPI

// Add the Picker to your body VStack
Picker("Data Source", selection: $dataSource) {
    Text("FlightAware API").tag(DataSource.flightAwareAPI)
    Text("Local Piaware").tag(DataSource.localPiaware)
}
.pickerStyle(SegmentedPickerStyle())

// Update the Button's action
Button(action: {
    if let location = locationManager.location {
        loading = true
        switch dataSource {
        case .flightAwareAPI:
            fetchAircraftData(location: location, radius: searchRadius / 69.0) { aircraftData in
                self.aircraftData = aircraftData
                speakAircraftData()
                loading = false
            }
        case .localPiaware:
            fetchAircraftDataFromPiaware { aircraftData in
                self.aircraftData = aircraftData
                speakAircraftData()
                loading = false
            }
        }
    }
}) {
    Image(systemName: "airplane")
        .font(.system(size: 72))
}
.padding()

// Add a new function to fetch data from the Piaware device
func fetchAircraftDataFromPiaware(completion: @escaping ([Flight]) -> Void) {
    // Replace with the actual Piaware API URL and format
    let piawareURL = "http://piaware.local/api/aircraft"

    AF.request(piawareURL, method: .get).responseJSON { response in
        switch response.result {
        case .success(let data):
            let json = JSON(data)
            let flights = parsePiawareData(json: json)
            DispatchQueue.main.async {
                completion(flights)
            }
        case .failure(let error):
            print("Error fetching aircraft data from Piaware:", error)
            DispatchQueue.main.async {
                completion([])
            }
        }
    }
}

// Add a new function to parse the Piaware data into the Flight struct
func parsePiawareData(json: JSON) -> [Flight] {
    // Parse the JSON data into the Flight struct
    // You may need to modify this based on the actual Piaware API format
    var flights: [Flight] = []
    for (_, subJson) in json["aircraft"] {
        // Parse the data and create Flight structs
        // ...
        flights.append(flight)
    }
    return flights
}
```

Please note that you'll need to replace the placeholders for the Piaware API URL and parsing with the actual information provided by your Piaware device.

_Prompt_: 
'responseJSON(queue:dataPreprocessor:emptyResponseCodes:emptyRequestMethods:options:completionHandler:)' is deprecated: responseJSON deprecated and will be removed in Alamofire 6. Use responseDecodable instead.

You're correct, responseJSON is deprecated in Alamofire 5 and will be removed in Alamofire 6. Since you're using SwiftyJSON for parsing JSON, you can update your fetchAircraftDataFromPiaware function using responseData to avoid the deprecation warning.

Here's an example of how you can modify the function:

```swift
func fetchAircraftDataFromPiaware(completion: @escaping ([Flight]) -> Void) {
    // Replace with the actual Piaware API URL and format
    let piawareURL = "http://piaware.local/api/aircraft"

    AF.request(piawareURL, method: .get).responseData { response in
        switch response.result {
        case .success(let data):
            let json = try! JSON(data: data)
            let flights = parsePiawareData(json: json)
            DispatchQueue.main.async {
                completion(flights)
            }
        case .failure(let error):
            print("Error fetching aircraft data from Piaware:", error)
            DispatchQueue.main.async {
                completion([])
            }
        }
    }
}
```

Using responseData will provide you with the raw Data object, which you can then use with SwiftyJSON to parse the response. Note that in this example, I've used try! to force-unwrap the JSON(data: data) initializer. Ideally, you should use do and catch to handle any errors that might occur during JSON parsing.

_Prompt_: 
Do you happen to know what API may be available on a piaware device?

PiAware devices, by default, provide a local API that serves data in JSON format from the ADS-B data feed. This data can be accessed through the device's IP address or hostname, typically on port 8080. The default API endpoint is /data/aircraft.json.

To access this data, you can use the following URL format:

```arduino
http://<piaware_device_ip_or_hostname>:8080/data/aircraft.json
```

Replace <piaware_device_ip_or_hostname> with the actual IP address or hostname of your PiAware device.

The JSON data returned by this API contains an array of aircraft objects with various fields like ICAO24 code, altitude, velocity, position, and more.

Here's an example of the JSON format:

```json
{
  "now": 1649224764.1,
  "messages": 48291,
  "aircraft": [
    {
      "hex": "a1b2c3",
      "flight": "UAL123  ",
      "alt_baro": 37025,
      "alt_geom": 37250,
      "gs": 431.3,
      "ias": 290,
      "tas": 420,
      "mach": 0.789,
      "track": 291.1,
      "baro_rate": 0,
      "geom_rate": 0,
      "squawk": "3311",
      "emergency": "none",
      "category": "A5",
      "nav_qnh": 1013.0,
      "nav_altitude_mcp": 37008,
      "nav_heading": 290.0,
      "lat": 37.000000,
      "lon": -122.000000,
      "nic": 8,
      "rc": 186,
      "seen_pos": 0.1,
      "version": 2,
      "nic_baro": 1,
      "nac_p": 10,
      "nac_v": 2,
      "sil": 3,
      "sil_type": "perhour",
      "gva": 2,
      "sda": 2,
      "mlat": [],
      "tisb": [],
      "messages": 251,
      "seen": 0.1,
      "rssi": -4.6
    }
  ]
}
```

Please note that the fields may vary depending on the available data for each aircraft.

To fetch and parse this data in your app, you'll need to adjust the fetchAircraftDataFromPiaware and parsePiawareData functions to accommodate the PiAware JSON format.

_Prompt_: 
Can you make that change for me? Also can you try to convert the parse data into a Flight struct?

Sure, I can help you with that. You'll need to make a few changes to your code to accommodate the PiAware JSON format and map it to your existing Flight struct. First, you'll need to modify the fetchAircraftDataFromPiaware function to point to the correct URL.

```swift
func fetchAircraftDataFromPiaware(completion: @escaping ([Flight]) -> Void) {
    let piawareURL = "http://piaware.local:8080/data/aircraft.json"

    AF.request(piawareURL, method: .get).responseData { response in
        switch response.result {
        case .success(let data):
            let json = try! JSON(data: data)
            let flights = parsePiawareData(json: json)
            DispatchQueue.main.async {
                completion(flights)
            }
        case .failure(let error):
            print("Error fetching aircraft data from Piaware:", error)
            DispatchQueue.main.async {
                completion([])
            }
        }
    }
}
```

Next, create the parsePiawareData function to convert the PiAware JSON data to an array of Flight structs. Note that not all fields from the PiAware API have a direct mapping to the Flight struct, so you might need to adjust the struct or make some assumptions based on the available data.

```swift
func parsePiawareData(json: JSON) -> [Flight] {
    let aircraftArray = json["aircraft"].arrayValue
    var flights: [Flight] = []

    for aircraft in aircraftArray {
        let flight = Flight(
            ident: aircraft["flight"].stringValue.trimmingCharacters(in: .whitespaces),
            fa_flight_id: nil,
            actual_off: nil,
            actual_on: nil,
            origin: nil,
            destination: nil,
            last_position: Flight.Position(
                fa_flight_id: nil,
                altitude: aircraft["alt_baro"].int,
                altitude_change: nil,
                groundspeed: aircraft["gs"].int,
                heading: aircraft["track"].int,
                latitude: aircraft["lat"].double,
                longitude: aircraft["lon"].double,
                timestamp: nil,
                update_type: nil
            ),
            aircraft_type: nil
        )
        flights.append(flight)
    }

    return flights
}
```

Keep in mind that the origin, destination, and aircraft_type fields are not directly available in the PiAware data. If you need this information, you may need to look for alternative sources or make additional API calls to retrieve the missing data. The example provided above simply sets those fields to nil.

Now, you can call the fetchAircraftDataFromPiaware function to get the aircraft data and update your app's UI accordingly.

