local TEST, CASE, CHECK = require("@vendor/testkit").test()
local hooks = require("@tests/hooks")
local logging = require("@src/logging")

local step_scheduler = hooks.scheduler.step

local text_pool = {
	"hello world",
	"lorem ipsum, epic text",
	"fluid is awesome",
}

local function wrap_clean(func: () -> ())
	return function()
		func()
		hooks.logging.on_warn(nil)
	end
end

local function shallow_warn_search(against: string, to_search: string): boolean
	return string.find(against, to_search) ~= nil
end

TEST(
	"logging.warn()",
	wrap_clean(function()
		CASE("works")
		for _, text in text_pool do
			local incoming_text: string = ""
			hooks.logging.on_warn(function(warn_text)
				incoming_text = warn_text
			end)

			logging.warn(text)
			CHECK(shallow_warn_search(incoming_text, text))
		end

		CASE("works multiple times")
		for _, text in text_pool do
			local log_count = 0
			hooks.logging.on_warn(function()
				log_count += 1
			end)

			for i = 1, 6 do
				logging.warn(text)
				CHECK(log_count == i)
			end
		end

		hooks.logging.on_warn(nil)
	end)
)

TEST(
	"logging.warn_suppresed()",
	wrap_clean(function()
		CASE("works once")
		for _, text in text_pool do
			local incoming_text: string = ""
			hooks.logging.on_warn(function(warn_text)
				incoming_text = warn_text
			end)

			logging.warn_suppressed(text)

			CHECK(shallow_warn_search(incoming_text, text))
		end

		CASE("does not work")
		for _, text in text_pool do
			local log_count = 0
			hooks.logging.on_warn(function()
				log_count += 1
			end)

			for i = 1, 6 do
				logging.warn_suppressed(text)
				CHECK(log_count == 0)
			end
		end

		CASE("should work after 10 seconds")
		step_scheduler(10)
		for _, text in text_pool do
			local incoming_text: string = ""
			hooks.logging.on_warn(function(warn_text)
				incoming_text = warn_text
			end)

			logging.warn_suppressed(text)

			CHECK(shallow_warn_search(incoming_text, text))
		end

		hooks.logging.on_warn(nil)
	end)
)
return nil
