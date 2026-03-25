defmodule Forth do
  @opaque evaluator :: %{}

  @doc """
  Create a new evaluator.
  """
  @spec new() :: evaluator
  def new() do
    %{:stack => [], :program => [], :dictionary => %{}}
  end

  @doc """
  Evaluate an input string, updating the evaluator state.
  """
  @spec eval(evaluator, String.t()) :: evaluator
  def eval(ev, s) do
    %{:stack => stack, :program => _program, :dictionary => dict} = ev
    program = tokenize(s)
    {result_stack, result_program, result_dict} = eval_rec(stack, program, dict)
    %{:stack => result_stack, :program => result_program, :dictionary => result_dict}
  end

  @std_words ["dup", "drop", "swap", "over"]

  defp eval_rec([], [], dict), do: {[], [], dict}
  defp eval_rec([{:number, _} | _] = stack, [], dict), do: {stack, [], dict}

  defp eval_rec(stack, [{:number, number} | program], dict),
    do: eval_rec([{:number, number} | stack], program, dict)

  defp eval_rec(stack, [:def, {type, word_name} | program], dict) do
    if not (type == :word or type == :math) do
      raise Forth.InvalidWord, word: word_name
    end

    {word_def, result_program} = Enum.split_while(program, &(&1 != :end))
    # word definition includes context dict
    result_dict = Map.put(dict, String.downcase(word_name), {word_def, dict})
    eval_rec(stack, tl(result_program), result_dict)
  end

  defp eval_rec(stack, [{:math, op} | program], dict) do
    if Map.has_key?(dict, op) do
      result_program = Enum.concat(expand_word(op, dict), program)
      eval_rec(stack, result_program, dict)
    else
      result_stack =
        case {op, stack} do
          {"+", [{:number, l}, {:number, r} | rest_op]} -> [{:number, r + l} | rest_op]
          {"-", [{:number, l}, {:number, r} | rest_op]} -> [{:number, r - l} | rest_op]
          {"*", [{:number, l}, {:number, r} | rest_op]} -> [{:number, r * l} | rest_op]
          {"/", [{:number, 0}, {:number, _} | _]} -> raise Forth.DivisionByZero
          {"/", [{:number, l}, {:number, r} | rest_op]} -> [{:number, div(r, l)} | rest_op]
          _ -> raise Forth.StackUnderflow
        end

      eval_rec(result_stack, program, dict)
    end
  end

  defp eval_rec(stack, [{:word, word} | program], dict) do
    norm_word = String.downcase(word)

    if Map.has_key?(dict, norm_word) do
      result_program = Enum.concat(expand_word(norm_word, dict), program)
      eval_rec(stack, result_program, dict)
    else
      result_stack =
        case {norm_word, stack} do
          {"dup", [item | _]} ->
            [item | stack]

          {"drop", [_item | rest_op]} ->
            rest_op

          {"swap", [item0, item1 | rest_op]} ->
            [item1 | [item0 | rest_op]]

          {"over", [_item0, item1 | _rest_op]} ->
            [item1 | stack]

          _ ->
            if Enum.member?(@std_words, norm_word) do
              raise Forth.StackUnderflow
            else
              raise Forth.UnknownWord, word: norm_word
            end
        end

      eval_rec(result_stack, program, dict)
    end
  end

  defp expand_word(word_name, dict) do
    norm_word_name = String.downcase(word_name)

    if Map.has_key?(dict, norm_word_name) do
      {word_def, word_dict} = Map.get(dict, norm_word_name)

      word_def
      |> Enum.flat_map(fn
        {:word, nested_word_name} -> expand_word(nested_word_name, word_dict)
        other -> [other]
      end)
    else
      [{:word, word_name}]
    end
  end

  defp tokenize_rec([], acc), do: acc |> Enum.reverse()

  defp tokenize_rec([t0 | rest], acc) do
    number = ~r/^\-*[0-9]+$/
    math = ~r/^[\-+*\/]$/

    tokenized =
      cond do
        Regex.match?(number, t0) -> {:number, elem(Integer.parse(t0), 0)}
        Regex.match?(math, t0) -> {:math, t0}
        t0 == ":" -> :def
        t0 == ";" -> :end
        true -> {:word, t0}
      end

    tokenize_rec(rest, [tokenized | acc])
  end

  @doc """
  Return the current stack as a string with the element on top of the stack
  being the rightmost element in the string.
  """
  @spec format_stack(evaluator) :: String.t()
  def format_stack(ev) do
    %{:stack => stack, :dictionary => _dict} = ev

    stack
    |> Enum.reverse()
    |> Enum.map(fn
      {:number, n} -> Integer.to_string(n)
      :def -> ":"
      :end -> ";"
      {:word, w} -> w
      {:math, m} -> m
    end)
    |> Enum.join(" ")
  end

  defmodule StackUnderflow do
    defexception []
    def message(_), do: "stack underflow"
  end

  defmodule InvalidWord do
    defexception word: nil
    def message(e), do: "invalid word: #{inspect(e.word)}"
  end

  defmodule UnknownWord do
    defexception word: nil
    def message(e), do: "unknown word: #{inspect(e.word)}"
  end

  defmodule DivisionByZero do
    defexception []
    def message(_), do: "division by zero"
  end

  defp tokenize(s) do
    Regex.split(~r/(*UTF)(*UCP)[^\w\/*+\-:;\p{S}]+/, s)
    |> tokenize_rec([])
  end
end
