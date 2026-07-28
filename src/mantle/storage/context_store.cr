# mantle/context_store.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "json"
require "digest/sha256"
require "../support/app_logger"
require "../support/status"
require "./context_node"

module Mantle::Storage
  # Base abstract class for context stores.
  class ContextStore
    property system_prompt : String
    property current_num_messages : Int32

    def initialize(@system_prompt : String)
      @current_num_messages = 0
    end

    def update_system_prompt(new_prompt : String)
      @system_prompt = new_prompt
    end

    def current_num_tokens : Int32
      current_view.sum do |msg|
        content_size = (msg.content || "").size
        tool_size = msg.tool_calls.try(&.to_json.size) || 0
        (content_size + tool_size) // 4
      end
    end

    def current_view : Array(Mantle::Message)
      [] of Mantle::Message
    end

    def add_message(
      label : String,
      message : String,
      tool_calls : Array(Mantle::Clients::ToolCall)? = nil,
      tool_call_id : String? = nil,
      token_count : Int32? = nil,
      turn_id : String? = nil,
      assembled_context : String? = nil,
      generation : GenerationParams? = nil
    )
    end

    def prune_to_tokens(target_tokens : Int32, summarizer : Proc(Array(Mantle::Message), String)? = nil, client : Mantle::Clients::Client? = nil) : Array(Mantle::Message)
      [] of Mantle::Message
    end

    def prune(num_to_prune : Int32, summarizer : Proc(Array(Mantle::Message), String)? = nil, client : Mantle::Clients::Client? = nil) : Array(Mantle::Message)
      [] of Mantle::Message
    end

    def clear
    end

    def last_turn_replayable? : Bool
      false
    end

    def last_user_message : Mantle::Message?
      nil
    end

    def last_bot_message : Mantle::Message?
      nil
    end

    def edit_last_bot_message(new_content : String) : Bool
      false
    end

    def pop_last_turn_for_replay : String?
      nil
    end

    protected def normalize_role(label : String) : String
      normalized = label.downcase
      case normalized
      when "user", "username"
        "user"
      when "bot", "botname", "assistant"
        "assistant"
      when "system"
        "system"
      when "tool"
        "tool"
      else
        raise ArgumentError.new("Invalid role label: #{label}. Must be user, assistant, system, or tool.")
      end
    end

    protected def validate_role(role : String)
      unless ["user", "assistant", "system", "tool"].includes?(role)
        raise ArgumentError.new("Invalid role: #{role}. Must be user, assistant, system, or tool.")
      end
    end
  end

  # Ephemeral sliding window context store.
  class EphemeralSlidingContextStore < ContextStore
    property messages_to_keep : Int32

    def initialize(system_prompt : String, messages_to_keep : Int32)
      super(system_prompt)
      @messages_to_keep = messages_to_keep
      @messages = Deque(Mantle::Message).new
    end

    def current_view : Array(Mantle::Message)
      result = [] of Mantle::Message
      result << Mantle::Message.new("system", @system_prompt) unless @system_prompt.empty?
      result.concat(@messages.to_a)
      result
    end

    def add_message(
      label : String,
      message : String,
      tool_calls : Array(Mantle::Clients::ToolCall)? = nil,
      tool_call_id : String? = nil,
      token_count : Int32? = nil,
      turn_id : String? = nil,
      assembled_context : String? = nil,
      generation : GenerationParams? = nil
    )
      role = normalize_role(label)
      @messages << Mantle::Message.new(role, message, tool_calls, tool_call_id)
      @messages.shift if @messages.size > @messages_to_keep
      @current_num_messages = @messages.size
    end

    def prune_to_tokens(target_tokens : Int32, summarizer : Proc(Array(Mantle::Message), String)? = nil, client : Mantle::Clients::Client? = nil) : Array(Mantle::Message)
      pruned_messages = [] of Mantle::Message
      while current_num_tokens > target_tokens && !@messages.empty?
        if @messages.first.role == "system" && @messages.size > 1
          system_msg = @messages.shift
          pruned_messages << @messages.shift
          @messages.unshift(system_msg)
        else
          pruned_messages << @messages.shift
        end
      end
      @current_num_messages = @messages.size
      return pruned_messages
    end

    def clear
      @messages.clear
      @current_num_messages = 0
    end

    def last_turn_replayable? : Bool
      return false if @messages.size < 2
      last_msg = @messages[-1]
      prev_msg = @messages[-2]

      return false unless last_msg.role == "assistant"
      return false unless prev_msg.role == "user"
      return false if last_msg.tool_calls.try(&.any?)
      return false if prev_msg.tool_calls.try(&.any?)
      return false if last_msg.tool_call_id || prev_msg.tool_call_id

      true
    end

    def last_user_message : Mantle::Message?
      last_turn_replayable? ? @messages[-2] : nil
    end

    def last_bot_message : Mantle::Message?
      last_turn_replayable? ? @messages[-1] : nil
    end

    def edit_last_bot_message(new_content : String) : Bool
      return false unless last_turn_replayable?
      last_msg = @messages[-1]
      @messages[-1] = Mantle::Message.new(last_msg.role, new_content, last_msg.tool_calls, last_msg.tool_call_id)
      true
    end

    def pop_last_turn_for_replay : String?
      return nil unless last_turn_replayable?
      bot_msg = @messages.pop
      user_msg = @messages.pop
      @current_num_messages = @messages.size
      user_msg.content
    end
  end

  # Node graph context store backing data to JSON with atomic updates and blob side-stores.
  class JSONContextStore < ContextStore
    property persist_system_prompt : Bool
    property context_file : String
    property active_leaf_id : String?
    property nodes : Hash(String, ContextNode)
    property summarizer : Proc(Array(Mantle::Message), String)?
    property client : Mantle::Clients::Client?

    private struct FileData
      include JSON::Serializable

      @[JSON::Field(default: 1)]
      property schema_version : Int32 = 1

      property active_leaf_id : String?

      @[JSON::Field(default: Hash(String, ContextNode).new)]
      property nodes : Hash(String, ContextNode) = Hash(String, ContextNode).new

      def initialize(@active_leaf_id : String?, @nodes : Hash(String, ContextNode) = Hash(String, ContextNode).new, @schema_version : Int32 = 1)
      end
    end

    def initialize(system_prompt : String, context_file : String, @persist_system_prompt : Bool = true, @summarizer : Proc(Array(Mantle::Message), String)? = nil, @client : Mantle::Clients::Client? = nil)
      super(system_prompt)
      @context_file = context_file
      @nodes = Hash(String, ContextNode).new
      @children_index = Hash(String, Array(String)).new
      @active_leaf_id = nil

      load_context_from_json
    end

    # Graph Traversal APIs

    def each_node(&block : ContextNode ->)
      @nodes.each_value(&block)
    end

    def ancestors(start_node_id : String?) : Array(ContextNode)
      result = [] of ContextNode
      curr_id = start_node_id
      visited = Set(String).new
      while curr_id
        break if visited.includes?(curr_id)
        visited.add(curr_id)
        if node = @nodes[curr_id]?
          result << node
          curr_id = node.parent_id
        else
          break
        end
      end
      result.reverse
    end

    def descendants(start_node_id : String) : Array(ContextNode)
      result = [] of ContextNode
      queue = Deque(String).new
      queue.concat(@children_index[start_node_id]? || [] of String)
      visited = Set(String).new
      while !queue.empty?
        curr = queue.pop
        next if visited.includes?(curr)
        visited.add(curr)
        if node = @nodes[curr]?
          result << node
          queue.concat(@children_index[curr]? || [] of String)
        end
      end
      result
    end

    def get_node_and_neighbors(target_node_id : String, k : Int32 = 1, turns : Bool = false) : Array(ContextNode)
      target_node = @nodes[target_node_id]?
      return [] of ContextNode unless target_node

      if turns && (target_turn = target_node.turn_id)
        branch = ancestors(@active_leaf_id)
        branch = ancestors(target_node_id) if branch.none? { |n| n.id == target_node_id }

        turn_ids = branch.compact_map(&.turn_id).uniq
        if idx = turn_ids.index(target_turn)
          min_idx = [0, idx - k].max
          max_idx = [turn_ids.size - 1, idx + k].min
          selected_turns = turn_ids[min_idx..max_idx].to_set
          branch.select { |n| n.turn_id && selected_turns.includes?(n.turn_id) }
        else
          [target_node]
        end
      else
        anc = ancestors(target_node_id)
        desc = descendants(target_node_id)
        anc_subset = anc.last([anc.size, k + 1].min)
        desc_subset = desc.first([desc.size, k].min)
        (anc_subset + desc_subset).uniq
      end
    end

    # Dynamic View Assembly & Positional Subsumption

    def current_view : Array(Mantle::Message)
      result = [] of Mantle::Message
      result << Mantle::Message.new("system", @system_prompt) unless @system_prompt.empty?

      branch = ancestors(@active_leaf_id)
      return result if branch.empty?

      subsumed_set = Set(String).new
      branch.each do |node|
        if subs = node.subsumes
          if subs.includes?(node.id)
            raise ArgumentError.new("Cyclic subsumption detected in node #{node.id}")
          end
          collect_transitive_subsumes(subs, subsumed_set)
        end
      end

      subsumed_to_summary = Hash(String, ContextNode).new
      branch.each do |node|
        if subs = node.subsumes
          subs.each do |sub_id|
            subsumed_to_summary[sub_id] = node
          end
        end
      end

      inserted_summaries = Set(String).new

      branch.each do |node|
        if subsumed_set.includes?(node.id)
          summary_node = subsumed_to_summary[node.id]?
          if summary_node && !inserted_summaries.includes?(summary_node.id) && !subsumed_set.includes?(summary_node.id)
            result << summary_node.message
            inserted_summaries.add(summary_node.id)
          end
        else
          if node.subsumes
            unless inserted_summaries.includes?(node.id)
              result << node.message
              inserted_summaries.add(node.id)
            end
          else
            result << node.message
          end
        end
      end

      result
    end

    def current_num_tokens : Int32
      current_view.sum do |msg|
        content_size = (msg.content || "").size
        tool_size = msg.tool_calls.try(&.to_json.size) || 0
        (content_size + tool_size) // 4
      end
    end

    def current_num_messages : Int32
      ancestors(@active_leaf_id).size
    end

    def add_message(
      label : String,
      message : String,
      tool_calls : Array(Mantle::Clients::ToolCall)? = nil,
      tool_call_id : String? = nil,
      token_count : Int32? = nil,
      turn_id : String? = nil,
      assembled_context : String? = nil,
      generation : GenerationParams? = nil
    )
      role = normalize_role(label)
      msg_obj = Mantle::Message.new(role, message, tool_calls, tool_call_id)

      tc = token_count || begin
        content_size = message.size
        tool_size = tool_calls.try(&.to_json.size) || 0
        [ (content_size + tool_size) // 4, 1 ].max
      end

      sha = assembled_context ? write_assembled_context(assembled_context) : nil

      node = ContextNode.new(
        message: msg_obj,
        token_count: tc,
        parent_id: @active_leaf_id,
        turn_id: turn_id,
        assembled_context_sha: sha,
        generation: generation
      )

      @nodes[node.id] = node
      if pid = node.parent_id
        (@children_index[pid] ||= [] of String) << node.id
      end
      @active_leaf_id = node.id
      @current_num_messages = ancestors(@active_leaf_id).size

      save_context_to_json
      node
    end

    def update_system_prompt(new_prompt : String)
      @system_prompt = new_prompt
      save_context_to_json
    end

    def set_active_leaf(node_id : String?)
      if node_id && !@nodes.has_key?(node_id)
        raise KeyError.new("Node ID #{node_id} does not exist in store")
      end
      @active_leaf_id = node_id
      @current_num_messages = ancestors(@active_leaf_id).size
      save_context_to_json
    end

    # Blob Side-Store Operations

    def blob_dir : String
      dir = File.join(File.dirname(@context_file), ".contexts", "blobs")
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      dir
    end

    def write_assembled_context(context_str : String) : String
      sha = Digest::SHA256.hexdigest(context_str)
      blob_path = File.join(blob_dir, sha)
      unless File.exists?(blob_path)
        File.write(blob_path, context_str)
      end
      sha
    end

    def read_assembled_context(sha : String) : String?
      blob_path = File.join(blob_dir, sha)
      File.exists?(blob_path) ? File.read(blob_path) : nil
    end

    # Pruning & Consolidation

    def prune_to_tokens(target_tokens : Int32, summarizer : Proc(Array(Mantle::Message), String)? = nil, client : Mantle::Clients::Client? = nil) : Array(Mantle::Message)
      pruned_messages = [] of Mantle::Message

      while current_num_tokens > target_tokens
        branch = ancestors(@active_leaf_id)
        subsumed_set = Set(String).new
        branch.each do |n|
          if subs = n.subsumes
            collect_transitive_subsumes(subs, subsumed_set)
          end
        end

        visible_nodes = [] of ContextNode
        branch.each do |n|
          next if subsumed_set.includes?(n.id) || n.subsumes
          visible_nodes << n
        end

        break if visible_nodes.empty?

        node_to_subsume = visible_nodes.first
        pruned_messages << node_to_subsume.message

        summary_text = generate_subsumed_summary(node_to_subsume, summarizer, client)
        summary_msg = Mantle::Message.new("system", summary_text)
        summary_node = ContextNode.new(
          message: summary_msg,
          token_count: [summary_text.size // 4, 1].max,
          parent_id: @active_leaf_id,
          subsumes: [node_to_subsume.id]
        )

        @nodes[summary_node.id] = summary_node
        if pid = summary_node.parent_id
          (@children_index[pid] ||= [] of String) << summary_node.id
        end
        @active_leaf_id = summary_node.id
      end

      @current_num_messages = ancestors(@active_leaf_id).size
      save_context_to_json
      return pruned_messages
    end

    def prune(num_to_prune : Int32, summarizer : Proc(Array(Mantle::Message), String)? = nil, client : Mantle::Clients::Client? = nil) : Array(Mantle::Message)
      pruned_messages = [] of Mantle::Message
      num_to_prune.times do
        branch = ancestors(@active_leaf_id)
        subsumed_set = Set(String).new
        branch.each do |n|
          if subs = n.subsumes
            collect_transitive_subsumes(subs, subsumed_set)
          end
        end

        visible_nodes = [] of ContextNode
        branch.each do |n|
          next if subsumed_set.includes?(n.id) || n.subsumes
          visible_nodes << n
        end

        break if visible_nodes.empty?
        node_to_subsume = visible_nodes.first
        pruned_messages << node_to_subsume.message

        summary_text = generate_subsumed_summary(node_to_subsume, summarizer, client)
        summary_msg = Mantle::Message.new("system", summary_text)
        summary_node = ContextNode.new(
          message: summary_msg,
          token_count: [summary_text.size // 4, 1].max,
          parent_id: @active_leaf_id,
          subsumes: [node_to_subsume.id]
        )

        @nodes[summary_node.id] = summary_node
        if pid = summary_node.parent_id
          (@children_index[pid] ||= [] of String) << summary_node.id
        end
        @active_leaf_id = summary_node.id
      end

      @current_num_messages = ancestors(@active_leaf_id).size
      save_context_to_json
      return pruned_messages
    end

    private def generate_subsumed_summary(node_to_subsume : ContextNode, summarizer_arg : Proc(Array(Mantle::Message), String)?, client_arg : Mantle::Clients::Client?) : String
      active_summarizer = summarizer_arg || @summarizer
      active_client = client_arg || @client

      subsumed_messages = [node_to_subsume.message]

      if active_summarizer
        begin
          res = active_summarizer.call(subsumed_messages)
          return res.strip unless res.strip.empty?
        rescue ex : Exception
          Mantle::Support::Log.warn { "Summarizer proc failed during context node subsumption: #{ex.message}" }
        end
      end

      if active_client
        begin
          prompt_messages = [
            Mantle::Message.new("system", "You are a context summarizer. Provide a concise 1-3 sentence summary capturing key facts, user requests, and decisions from the following subsumed conversation turn(s)."),
            Mantle::Message.new("user", subsumed_messages.map { |m| "[#{m.role}]: #{m.content}" }.join("\n"))
          ]
          response = active_client.execute(prompt_messages)
          if content = response.content.try(&.strip)
            return content unless content.empty?
          end
        rescue ex : Exception
          Mantle::Support::Log.warn { "LLM client call failed during context node subsumption: #{ex.message}" }
        end
      end

      fallback_id = node_to_subsume.turn_id ? "turn #{node_to_subsume.turn_id}" : "node #{node_to_subsume.id}"
      Mantle::Support::Log.warn { "Using fallback text for subsumed context node #{node_to_subsume.id}" }
      "[Context subsumed from #{fallback_id}]"
    end

    def clear
      @nodes.clear
      @children_index.clear
      @active_leaf_id = nil
      @current_num_messages = 0
      save_context_to_json
    end

    def last_turn_replayable? : Bool
      branch = ancestors(@active_leaf_id)
      return false if branch.size < 2
      last_node = branch[-1]
      prev_node = branch[-2]

      return false unless last_node.message.role == "assistant"
      return false unless prev_node.message.role == "user"
      return false if last_node.message.tool_calls.try(&.any?)
      return false if prev_node.message.tool_calls.try(&.any?)
      return false if last_node.message.tool_call_id || prev_node.message.tool_call_id

      true
    end

    def last_user_message : Mantle::Message?
      return nil unless last_turn_replayable?
      branch = ancestors(@active_leaf_id)
      branch[-2].message
    end

    def last_bot_message : Mantle::Message?
      return nil unless last_turn_replayable?
      branch = ancestors(@active_leaf_id)
      branch[-1].message
    end

    def edit_last_bot_message(new_content : String) : Bool
      return false unless last_turn_replayable?
      branch = ancestors(@active_leaf_id)
      user_node = branch[-2]
      last_node = branch[-1]

      new_msg = Mantle::Message.new("assistant", new_content, last_node.message.tool_calls, last_node.message.tool_call_id)
      new_node = ContextNode.new(
        message: new_msg,
        token_count: [new_content.size // 4, 1].max,
        parent_id: user_node.id
      )
      @nodes[new_node.id] = new_node
      (@children_index[user_node.id] ||= [] of String) << new_node.id
      @active_leaf_id = new_node.id

      save_context_to_json
      true
    end

    def pop_last_turn_for_replay : String?
      return nil unless last_turn_replayable?
      branch = ancestors(@active_leaf_id)
      user_node = branch[-2]

      @active_leaf_id = user_node.parent_id
      @current_num_messages = ancestors(@active_leaf_id).size
      save_context_to_json
      user_node.message.content
    end

    # Atomic Persistence

    def save_context_to_json : Nil
      begin
        data = FileData.new(@active_leaf_id, @nodes)
        tmp_file = "#{@context_file}.tmp"
        File.open(tmp_file, "w") { |f| data.to_json(f) }
        File.rename(tmp_file, @context_file)
      rescue e : Exception
        Mantle::Support::Log.error { "Failed to save context to #{@context_file}: #{e.message}" }
      end
    end

    def load_context_from_json
      begin
        data = File.open(@context_file, "r") { |f| FileData.from_json(f) }
        @nodes = data.nodes
        @active_leaf_id = data.active_leaf_id
        rebuild_children_index
        @current_num_messages = ancestors(@active_leaf_id).size
        Mantle::Support::Log.info { "Loaded context from #{@context_file}" }
      rescue e : File::NotFoundError
        save_context_to_json
        Mantle::Support::Log.warn { "Context file was not found - creating a new one." }
        Mantle.emit_status(:new_context_file)
      rescue e : Exception
        Mantle::Support::Log.warn { "Context file #{@context_file} could not be parsed as graph data (#{e.message}) - re-initializing." }
        clear
        Mantle.emit_status(:new_context_file)
      end
    end

    private def rebuild_children_index
      @children_index.clear
      @nodes.each_value do |node|
        if parent_id = node.parent_id
          (@children_index[parent_id] ||= [] of String) << node.id
        end
      end
    end

    private def collect_transitive_subsumes(direct_subs : Array(String), set : Set(String))
      direct_subs.each do |sub_id|
        next if set.includes?(sub_id)
        set.add(sub_id)
        if node = @nodes[sub_id]?
          if child_subs = node.subsumes
            collect_transitive_subsumes(child_subs, set)
          end
        end
      end
    end
  end
end
