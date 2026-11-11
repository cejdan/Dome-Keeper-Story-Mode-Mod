extends RefCounted

# Shared lava numbers for the user to tune (lava/lava_field.gd uses them).
# Starting values; the lava tickets (#41-#48) add theirs here.

# --- cooling (#41) ---------------------------------------------------------
# A lava cell cools only when the cell below holds no lava and its top is open
# to air: the cell above is open and holds no lava, or the cell itself isn't full.
# "Holds lava" means at least HOLDS_MASS; "full" means at least FULL_MASS.
const HOLDS_MASS := 0.12
const FULL_MASS := 0.9
