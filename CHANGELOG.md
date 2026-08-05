r30:

- Add AF.AttachTransientScrollBar (template-free fade-in/out scroll bar with inactivity fade and drag hold)
- Add AF.CreateTreeList (scrollable tree list: pooled rows, accent highlight, chevron toggles, animated expand/collapse, compact mode with icon-only leaf rows and chevron+icon parent rows, atlas/texture icon shapes with a unified textureTint desaturate+tint option; expansion state is shared between compact and expanded presentations with a single scroll offset)
- Add AF.CreateSidebarRail (sidebar rail wrapping a tree list: manual SetCollapsed/GetCollapsed/ToggleCollapsed/SetOnCollapsedChanged collapse API, presentation-width publication, content inset helpers)
- Add Bag_All/Bag_Empty/Bag_IndividualBags/Bag_Misc adaptive icons for bag sidebar fallback states (the rest of the original Bag_* set was pruned after BFInfinite's Bags sidebar v2 moved consumable-subclass and equipment-slot icons to native client art)

[View Full Changelog](https://github.com/enderneko/AbstractWidgets/compare/r19...83bd2eb1a4ea2be3776b3f9366990a6836de39eb)

- Remove TooltipDataHandlerMixin and ClearHandlerInfo call
