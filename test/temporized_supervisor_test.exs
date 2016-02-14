defmodule TestSup1 do
  use TemporizedSupervisor
end

defmodule TemporizedSupervisorTest do
  use ExUnit.Case

  test "the truth" do
    assert 1 + 1 == 2
  end
end
