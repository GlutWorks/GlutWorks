-- Weather types. Values are 0..1 except `temperature`, a °C offset on the outdoor temperature. `next` holds the
-- weights of the types that may follow this one; a type missing from it can never follow, so the sky only
-- changes one step at a time (clear -> cloudy -> drizzle/rain -> storm and back). Precipitation falls as snow
-- when the outdoor temperature is at or below ix.weather.SNOW_TEMPERATURE.
ix.weather.types = {
	clear = {
		name = "weatherClear",
		precipitation = 0, wind = 0.15, cloud = 0, fog = 0, temperature = 2, thunder = false,
		next = {clear = 2, cloudy = 3, fog = 1}
	},
	cloudy = {
		name = "weatherCloudy",
		precipitation = 0, wind = 0.3, cloud = 0.6, fog = 0.05, temperature = 0, thunder = false,
		next = {clear = 2, cloudy = 1, fog = 1, drizzle = 2, rain = 1}
	},
	fog = {
		name = "weatherFog",
		precipitation = 0, wind = 0.05, cloud = 0.45, fog = 0.85, temperature = -1, thunder = false,
		next = {clear = 1, cloudy = 2, fog = 1, drizzle = 1}
	},
	drizzle = {
		name = "weatherDrizzle",
		precipitation = 0.3, wind = 0.25, cloud = 0.7, fog = 0.15, temperature = -2, thunder = false,
		next = {cloudy = 2, fog = 1, drizzle = 1, rain = 2}
	},
	rain = {
		name = "weatherRain",
		precipitation = 0.7, wind = 0.45, cloud = 0.85, fog = 0.2, temperature = -3, thunder = false,
		next = {cloudy = 1, drizzle = 2, rain = 1, storm = 1}
	},
	storm = {
		name = "weatherStorm",
		precipitation = 1, wind = 0.9, cloud = 1, fog = 0.25, temperature = -5, thunder = true,
		next = {drizzle = 1, rain = 3}
	}
}
