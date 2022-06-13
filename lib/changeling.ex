defmodule Changeling do
  @moduledoc """
  Elixir refactoring functions.
  """

  alias Sourceror.Zipper, as: Z

  defp d({{n, _, _}, _} = zipper, lab) do
    IO.inspect(n, label: lab)
    zipper
  end

  defp d(zipper, _), do: zipper

  defp remove_range({{:def, meta, [{marker, _, _}, _]}, _list} = zipper, from, to, acc) do
    acc =
      if meta[:line] < from do
        put_in(acc.def, marker)
      else
        acc
      end

    zipper |> Z.next() |> remove_range(from, to, acc)
  end

  defp remove_range({{marker, meta, _children}, _list} = zipper, from, to, acc) do
    if Z.end?(zipper) do
      d(zipper, "end")
      {zipper, put_in(acc.lines, Enum.reverse(acc.lines))}
    else
      if meta[:line] < from || meta[:line] > to || marker == :__block__ do
        # if Z.root(zipper) == Z.node(zipper) do
        zipper |> Z.next() |> remove_range(from, to, acc)
      else
        acc = put_in(acc.lines, [Z.node(zipper) | acc.lines])

        if is_nil(acc.replace_with) do
          zipper |> Z.remove() |> Z.next() |> remove_range(from, to, acc)
        else
          function_name = acc.replace_with
          acc = put_in(acc.replace_with, nil)

          zipper
          |> Z.replace({function_name, [], []})
          |> Z.next()
          |> remove_range(from, to, acc)
        end
      end
    end
  end

  defp remove_range(zipper, from, to, acc) do
    if Z.end?(zipper) do
      d(zipper, "end2")
      {zipper, put_in(acc.lines, Enum.reverse(acc.lines))}
    else
      d(zipper, "remove2")
      zipper |> Z.next() |> remove_range(from, to, acc)
    end
  end

  @doc """
  Return zipper containing AST for lines in the range from-to.
  """
  def extract_lines(zipper, from, to, replace_with \\ nil) do
    remove_range(zipper, from, to, %{lines: [], def: nil, replace_with: replace_with})
  end

  def extract_function(zipper, from, to, function_name) do
    {{quoted, :end}, acc} = extract_lines(zipper, from, to, function_name)
    zipper = Z.zip(quoted)
    enclosing = acc.def

    args = []
    # [
    #   {:one, [trailing_comments: [], leading_comments: [], line: 2, column: 11],
    #    nil},
    #   {:two, [trailing_comments: [], leading_comments: [], line: 2, column: 16],
    #    nil}
    # ]
    extracted =
      {:def, [do: [], end: []],
       [
         {function_name, [], args},
         [
           {{:__block__, [], [:do]}, {:__block__, [], acc.lines}}
         ]
       ]}

    declares =
      extracted
      |> Z.zip()
      |> Z.find(fn
        {:=, _, [{_, _, _}, _]} -> true
        _ -> false
      end)

    {zipper, extracted} =
      if is_nil(declares) do
        {zipper, extracted}
      else
        {:=, _, [{var, _, _}, _]} = declares |> Z.node()

        zipper =
          Z.find(Z.top(zipper), fn
            {^function_name, [], []} -> true
            _ -> false
          end)

        {Z.replace(
           zipper,
           {:=, [], [{var, [], nil}, {function_name, [], []}]}
         ),
         {:def, [do: [], end: []],
          [
            {function_name, [], args},
            [
              {{:__block__, [], [:do]},
               {:__block__, [], Enum.concat(acc.lines, [{var, [], nil}])}}
            ]
          ]}}
      end

    zipper =
      Z.find(Z.top(zipper), fn
        {:def, _meta, [{^enclosing, _, _}, _]} -> true
        _ -> false
      end)

    zipper
    |> Z.insert_right(extracted)
    |> fix_block()
    |> Z.root()
  end

  defp fix_block(zipper) do
    case Z.find(Z.top(zipper), :next, fn
           {:{}, [], _children} -> true
           _ -> false
         end) do
      nil ->
        zipper

      {{:{}, [], [block | defs]}, meta} ->
        node = {
          block,
          {:__block__, [trailing_comments: [], leading_comments: []], defs}
        }

        {node, meta}
    end
  end
end
