return {
	CLIENT_REEL_READY_TIMEOUT = 2, -- Player gets a while to get ready
	
	EVENT_LIFESPAN = 20,
	
	DEFAULT_FISH_LENGTH = 5, -- How long does it take to catch a fish
	
	RANGE = 15,
	
	ERROR_FLAGS = {
		ARG = 0b0001, -- Invalid argument
		RUNNING = 0b0010, -- Already running event
		CHARACTER = 0b0100, -- No player character
	}
}