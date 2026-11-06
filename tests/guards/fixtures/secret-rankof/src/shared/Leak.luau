--!strict
-- This comment names rankOf and is NOT the violation: R5 scans stripComments(raw), so a comment is
-- invisible to it. The string literal below IS the violation, because sf.text keeps string
-- literals. That asymmetry is the whole point of D-37 as corrected 2026-11-05.
local SECRET_FIELD = "rankOf"
return { SECRET_FIELD = SECRET_FIELD }
