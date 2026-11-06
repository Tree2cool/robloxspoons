--!strict
-- This file names rankOf only in this comment. R5 scans stripComments(raw), so a comment is
-- invisible to it, and a comment leaks nothing. This is the negative control for secret-rankof:
-- it proves the scope is code plus string literals, not "any mention".
local ANSWER = 42
return { ANSWER = ANSWER }
