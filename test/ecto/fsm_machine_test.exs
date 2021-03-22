defmodule Ecto.FSM.MachineTest do
  use ExUnit.Case

  require Locker

  alias Ecto.Changeset
  alias Ecto.FSM.Machine

  doctest Ecto.FSM.Machine

  describe "Simple handler" do
    setup :new_locker

    test ".fsm/1", %{locker: s} do
      assert match?(
               %{
                 {:locked, :_} => {Locker, [:locked]},
                 {:locked, :one} => {Locker, [:one]},
                 {:one, :_} => {Locker, [:locked]},
                 {:one, :two} => {Locker, [:two]},
                 {:two, :_} => {Locker, [:locked]},
                 {:two, :three} => {Locker, [:three]},
                 {:three, :_} => {Locker, [:locked]},
                 {:three, :four} => {Locker, [:unlocked]}
               },
               Machine.fsm(s)
             )
    end

    test ".event_bypasses/1", %{locker: s} do
      res = Machine.event_bypasses(s)

      assert match?(%{:c => Locker}, res)
    end

    test ".find_handler/1", %{locker: s} do
      # State unlocked is only state with no match all
      s = %{s | status: :unlocked}

      assert match?(Locker, Machine.find_handler({s, :lock}))
      assert match?(nil, Machine.find_handler({s, :non_existing_transition}))
    end

    test ".find_bypass_handler/2", %{locker: s} do
      assert match?(Locker, Machine.find_bypass_handler(s, :c))
      assert match?(nil, Machine.find_bypass_handler(s, :non_existing_bypass))
    end

    test ".infos/2", %{locker: s} do
      assert match?(
               %{
                 {:event_doc, :c} => "Reset locker",
                 {:transition_doc, :locked, :_} => "Invalid input: :locked",
                 {:transition_doc, :locked, :one} => "Valid input: 1",
                 {:transition_doc, :one, :_} => "Invalid input: :locked",
                 {:transition_doc, :one, :two} => "Valid input: 1,2",
                 {:transition_doc, :three, :_} => "Invalid input: :locked",
                 {:transition_doc, :three, :four} => "Valid input: 1,2,3,4",
                 {:transition_doc, :two, :_} => "Invalid input: :locked",
                 {:transition_doc, :two, :three} => "Valid input: 1,2,3",
                 {:transition_doc, :unlocked, :keep_multi} => _,
                 {:transition_doc, :unlocked, :lock} => _,
                 {:transition_doc, :unlocked, :next_multi} => _
               },
               Machine.infos(s, :two)
             )
    end

    test ".find_info/2", %{locker: s} do
      assert match?({:transition, _}, Machine.find_info(s, :one))
      assert match?(nil, Machine.find_info(s, :unknown))
      assert match?({:bypass, _}, Machine.find_info(s, :c))
    end

    test ".available_actions/1", %{locker: s} do
      assert match?([:_, :one, :c], Machine.available_actions(s))

      assert match?(
               [:keep_multi, :lock, :next_multi, :c],
               Machine.available_actions(%{s | status: :unlocked})
             )
    end

    test ".action_available?/2", %{locker: s} do
      # Defined transition
      assert match?(true, Machine.action_available?(s, :one))

      # Match ':_' transition
      assert match?(true, Machine.action_available?(s, :unknown))

      # Bypass
      assert match?(true, Machine.action_available?(s, :c))

      # State `:unlocked` has no match all
      s = %{s | status: :unlocked}
      assert match?(true, Machine.action_available?(s, :lock))
      assert match?(false, Machine.action_available?(s, :unknown))
    end

    test ".event/2", %{locker: s} do
      # State change
      assert match?(
               {:ok, %Changeset{changes: %{status: :one}}},
               Machine.event(s, {:one, nil})
             )
    end
  end

  defp new_locker(_ctx) do
    {:ok, locker: %Locker.Schema{status: :locked}}
  end
end
