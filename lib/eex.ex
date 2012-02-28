defmodule EEx do
  def compile(source, engine // EEx::Engine) do
    EEx::Compiler.compile(source, engine)
  end
end

defexception EEx::SyntaxError, message: nil

defrecord EEx::State, engine: nil, dict: [], filename: nil, line: 0

defmodule EEx::Compiler do
  def compile(source, engine) do
    tokens = EEx::Tokenizer.tokenize(source, 1)
    state = EEx::State.new(engine: engine)
    generate_buffer(tokens, "", [], state)
  end

  defp generate_buffer([{ :text, _line, chars }|t], buffer, scope, state) do
    buffer = state.engine.handle_text(buffer, chars)
    generate_buffer(t, buffer, scope, state)
  end

  # TODO: use filename
  defp generate_buffer([{ :expr, line, mark, chars }|t], buffer, scope, state) do
    expr = { :__BLOCK__, 0, Erlang.elixir_translator.forms(chars, line, 'nofile') }
    buffer = state.engine.handle_expr(buffer, mark, expr)
    generate_buffer(t, buffer, scope, state)
  end

  defp generate_buffer([{ :start_expr, line, _, chars }|t], buffer, scope, state) do
    { contents, t } = generate_buffer(t, "", [chars|scope], state.dict([]).line(line))
    buffer = state.engine.handle_expr(buffer, '=', contents)
    generate_buffer(t, buffer, scope, state.dict([]))
  end

  defp generate_buffer([{ :middle_expr, _, _, chars }|t], buffer, [current|scope], state) do
    { wrapped, state } = wrap_expr(current, buffer, chars, state)
    generate_buffer(t, "", [wrapped|scope], state)
  end

  defp generate_buffer([{ :end_expr, _, _, chars }|t], buffer, [current|_], state) do
    { wrapped, state } = wrap_expr(current, buffer, chars, state)
    tuples = { :__BLOCK__, 0, Erlang.elixir_translator.forms(wrapped, state.line, 'nofile') }
    buffer = insert_quotes(tuples, state.dict)
    { buffer, t }
  end

  defp generate_buffer([{ :end_expr, _, _, chars }|_], _buffer, [], _state) do
    raise SyntaxError, message: "unexpected token: #{inspect chars}"
  end

  defp generate_buffer([], buffer, [], _state) do
    buffer
  end

  defp generate_buffer([], _buffer, _scope, _state) do
    raise SyntaxError, message: "undetermined end of string"
  end

  ####

  def wrap_expr(current, buffer, chars, state) do
    key = length(state.dict)
    placeholder = '__EEX__(' ++ integer_to_list(key) ++ ');'

    { current ++ placeholder ++ chars, state.merge_dict([{key, buffer}]) }
  end

  ###

  def insert_quotes( { :__EEX__, _, [key] }, dict) do
    Orddict.get(dict, key)
  end

  def insert_quotes({ left, line, right }, dict) do
    { insert_quotes(left, dict), line, insert_quotes(right, dict) }
  end

  def insert_quotes({ left, right }, dict) do
    { insert_quotes(left, dict), insert_quotes(right, dict) }
  end

  def insert_quotes(list, dict) when is_list(list) do
    Enum.map list, insert_quotes(&1, dict)
  end

  def insert_quotes(other, _dict) do
    other
  end
end
