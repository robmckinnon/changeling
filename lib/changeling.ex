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

  defp remove_range({{:def, _meta, [{marker, _, _}, _]}, _list} = zipper, from, to, acc) do
    acc = put_in(acc.def, marker)
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
        zipper |> Z.remove() |> Z.next() |> remove_range(from, to, acc)
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
  def extract_lines(zipper, from, to) do
    remove_range(zipper, from, to, %{lines: [], def: nil})
  end

  def extract_function(zipper, from, to, function_name) do
    {{quoted, :end}, acc} = extract_lines(zipper, from, to)
    zipper = Z.zip(quoted)
    enclosing = acc.def

    zipper =
      Z.find(Z.top(zipper), :next, fn
        {:def, _meta, [{^enclosing, _, _}, _]} -> true
        _ -> false
      end)

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

    # {_x, meta} = zipper
    # IO.inspect([extracted | meta.r || []])

    zipper = Z.insert_right(zipper, extracted)

    {{:{}, [], [block | defs]}, meta} =
      Z.find(Z.top(zipper), :next, fn
        {:{}, [], _children} -> true
        _ -> false
      end)

    node = {
      block,
      {:__block__, [trailing_comments: [], leading_comments: []], defs}
    }

    {node, meta} |> Z.root()
  end

  def next_please(zipper) do
    if Z.end?(zipper) do
      zipper
    else
      next_please(Z.next(zipper))
    end
  end
end
