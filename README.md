# airplanesoverhead

# Overview
iOS App that announces aircraft that are flying overhead. I am an aviation enthusiast and planes fly oveer my house a lot so I thought of a silly app that I could have my phone automatically tell me what plane just flew overhead and its altitude, speed, and when possible its origin and destination.

# Background
This is a hobby iOS project idea where I used ChatGPT to write all of the code starting with:

```
My Prompt: Write an iOS app that uses the FlightAware API to determine what airplanes are 
flying overhead right now and announces the name and type of aircraft using 
text to speech APIs on iOS
```

My goal was to see how far I could get with building a program **without writing the actual code**. And that is the code I have checked in here. I made it a point to not change the code it generated. The result is a working iOS app that I have uploaded here.

# Features
Over the course of several chat sessions I kept asking for new features incrementally once it had created a working initial version.

- Fetches data from FlightAware API upon tapping the airplane button tap
- Selectable range form the user's current location to limit the search
- List view of the aircraft found
- Speaks the aircraft information
- Renders each aircraft location on a map view
- Uses manufacturer lookups to turn aircraft codes into full aircraft names
- Support alternate data source of a local Piaware device to get similar information using a local ADS-B receiver on your local network (saves FlightAware API costs)

# ChatGPT Sessions
Take a look at the [saved sessions](https://github.com/jkoehl/airplanesoverhead/tree/main/ChatGPTSessions/) to see what my inputs were to ChatGPT and what it generated. This willl give some insight into how this came together and you will probably be suprised by what it can do.

<img src="./Screenshot1.jpeg" alt="Screenshot 1" width="375">

# ChatGPT Observations and Insights

- 
