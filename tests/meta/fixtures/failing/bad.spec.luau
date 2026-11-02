--!strict
return function(t)
	t.test("this test is supposed to fail", function()
		t.equal(1, 2, "deliberate failure proving the runner can fail")
	end)
end
