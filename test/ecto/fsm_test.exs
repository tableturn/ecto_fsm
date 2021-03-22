defmodule Ecto.FSM.NotationTest do
  use ExUnit.Case

  doctest Ecto.FSM

  describe ".transition/2" do
    setup do
      Code.compiler_options(ignore_module_conflict: true)

      on_exit(fn ->
        Code.compiler_options(ignore_module_conflict: false)
      end)
    end

    test "...base transition" do
      {:module, mod, _, _} =
        defmodule TestFsm do
          use Ecto.FSM

          transition init({:action, _}, s) do
            {:next_state, :end, s}
          end
        end

      assert match?(%{{:init, :action} => {^mod, [:end]}}, mod.fsm())
    end

    test "...default transition" do
      {:module, mod, _, _} =
        defmodule TestFsm do
          use Ecto.FSM

          transition init({:action, _}, s) do
            {:next_state, :end, s}
          end

          transition init({_, _}, s) do
            {:next_state, :error, s}
          end
        end

      assert match?(
               %{
                 {:init, :action} => {^mod, [:end]},
                 {:init, :_} => {^mod, [:error]}
               },
               mod.fsm()
             )
    end
  end

  describe ".bypass/2" do
    setup do
      Code.compiler_options(ignore_module_conflict: true)

      on_exit(fn ->
        Code.compiler_options(ignore_module_conflict: false)
      end)
    end

    test "...base bypass" do
      {:module, mod, _, _} =
        defmodule TestFsm do
          use Ecto.FSM

          bypass goto_s1(_, s) do
            {:next_state, :s1, s}
          end
        end

      assert match?(%{:goto_s1 => ^mod}, mod.event_bypasses())
    end
  end


  describe ".states_names/0" do
    setup do
      Code.compiler_options(ignore_module_conflict: true)

      on_exit(fn ->
        Code.compiler_options(ignore_module_conflict: false)
      end)
    end

    test "...base states_names" do
      {:module, mod, _, _} =
        defmodule TestFsm do
          use Ecto.FSM

          transition s1({:goto_s2, nil}, s) do
            {:next_state, :s2, s}
          end

          transition s2({:goto_s3, nil}, s) do
            {:next_state, :s3, s}
          end
        end
      
      assert match?([:s1, :s2, :s3], mod.states_names() |> Enum.sort())
    end
  end
end
