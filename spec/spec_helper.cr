require "spec"
require "../src/mantle"
class DummyLogger < Mantle::Logger
    property last_message : String?
    property targeted_file : String?

    def log(message : String, label : String, file : String)
        @last_message = label + "\n" + message
        @targeted_file = file
    end
end
