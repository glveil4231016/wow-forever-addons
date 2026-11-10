local ADDON, PB = ...
local U = PB.Util

PB.Test.it("money format zero", function() PB.Test.eq(U.FormatMoney(0), "0铜") end)
PB.Test.it("money format copper only", function() PB.Test.eq(U.FormatMoney(45), "45铜") end)
PB.Test.it("money format full", function() PB.Test.eq(U.FormatMoney(12345), "1金 23银 45铜") end)
PB.Test.it("money format negative", function() PB.Test.eq(U.FormatMoney(-12345), "-1金 23银 45铜") end)
PB.Test.it("parse plain", function() PB.Test.eq(U.ParseMoney("12345"), 12345) end)
PB.Test.it("parse zh", function() PB.Test.eq(U.ParseMoney("1金23银45铜"), 12345) end)
PB.Test.it("parse partial", function() PB.Test.eq(U.ParseMoney("1金45铜"), 10045) end)
PB.Test.it("parse invalid", function() PB.Test.eq(U.ParseMoney("abc"), nil) end)
PB.Test.it("median odd", function() PB.Test.near(U.Median({ 5, 1, 3 }), 3) end)
PB.Test.it("median even", function() PB.Test.near(U.Median({ 4, 1, 3, 2 }), 2.5) end)
PB.Test.it("median empty", function() PB.Test.eq(U.Median({}), nil) end)
PB.Test.it("today numeric", function() PB.Test.eq(type(U.Today()), "number") end)
