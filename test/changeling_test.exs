defmodule ChangelingTest do
  use ExUnit.Case
  # doctest Changeling
  alias Sourceror.Zipper, as: Z

  setup do
    {:ok,
     quoted:
       """
       defmodule Baz do
         def foo(one, two) do
           three = 3
           IO.inspect(one)
           IO.inspect(two)
           IO.inspect(three)
           four = 4
           IO.inspect(three)
           IO.inspect(four)
         end
       end
       """
       |> Sourceror.parse_string!()}
  end

  describe "extract_function" do
    test "extract one line to function", %{quoted: quoted} do
      zipper = Changeling.extract_function(Z.zip(quoted), 3, 3, :bar)
      source = Sourceror.to_string(zipper)

      assert [
               "defmodule Baz do",
               "  def foo(one, two) do",
               "    three = bar()",
               "    IO.inspect(one)",
               "    IO.inspect(two)",
               "    IO.inspect(three)",
               "    four = 4",
               "    IO.inspect(three)",
               "    IO.inspect(four)",
               "  end",
               "",
               "  def bar() do",
               "    three = 3",
               "    three",
               "  end",
               "end"
             ] ==
               source |> String.split("\n")

      Code.eval_string(source)
    end

    test "extract multiple lines to function", %{quoted: quoted} do
      zipper = Changeling.extract_function(Z.zip(quoted), 3, 4, :bar)
      source = Sourceror.to_string(zipper)

      assert [
               "defmodule Baz do",
               "  def foo(one, two) do",
               "    three = bar(one)",
               "    IO.inspect(two)",
               "    IO.inspect(three)",
               "    four = 4",
               "    IO.inspect(three)",
               "    IO.inspect(four)",
               "  end",
               "",
               "  def bar(one) do",
               "    three = 3",
               "    IO.inspect(one)",
               "    three",
               "  end",
               "end"
             ] ==
               source |> String.split("\n")

      Code.eval_string(source)
    end

    test "extract multiple lines with multiple returns to function", %{quoted: quoted} do
      zipper = Changeling.extract_function(Z.zip(quoted), 3, 7, :bar)
      source = Sourceror.to_string(zipper)

      assert [
               "defmodule Baz do",
               "  def foo(one, two) do",
               "    {three, four} = bar(one, two)",
               "    IO.inspect(three)",
               "    IO.inspect(four)",
               "  end",
               "",
               "  def bar(one, two) do",
               "    three = 3",
               "    IO.inspect(one)",
               "    IO.inspect(two)",
               "    IO.inspect(three)",
               "    four = 4",
               "    {three, four}",
               "  end",
               "end"
             ] ==
               source |> String.split("\n")

      Code.eval_string(source)
    end
  end

  describe "extract_lines/3" do
    test "extract one line to function", %{quoted: quoted} do
      {zipper, lines} = Changeling.extract_lines(Z.zip(quoted), 3, 3)

      assert "{defmodule Baz do\n   def foo(one, two) do\n     IO.inspect(one)\n     IO.inspect(two)\n     IO.inspect(three)\n     four = 4\n     IO.inspect(three)\n     IO.inspect(four)\n   end\n end, :end}" =
               Sourceror.to_string(zipper)

      assert ["{:def, :foo}", "{:lines, [three = 3]}", _] =
               lines |> Enum.map(&Sourceror.to_string(&1))
    end

    test "extract multiple lines to function", %{quoted: quoted} do
      {zipper, lines} = Changeling.extract_lines(Z.zip(quoted), 3, 4)

      assert "{defmodule Baz do\n   def foo(one, two) do\n     IO.inspect(two)\n     IO.inspect(three)\n     four = 4\n     IO.inspect(three)\n     IO.inspect(four)\n   end\n end, :end}" =
               Sourceror.to_string(zipper)

      assert ["{:def, :foo}", "{:lines, [three = 3, IO.inspect(one)]}", _] =
               lines |> Enum.map(&Sourceror.to_string(&1))
    end
  end
end
