--!strict
return function(t)
	t.test("this test is supposed to pass", function()
		t.equal(1, 1)
	end)
end
