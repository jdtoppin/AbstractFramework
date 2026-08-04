[View Full Changelog](https://github.com/enderneko/AbstractWidgets/compare/r19...83bd2eb1a4ea2be3776b3f9366990a6836de39eb)

- Remove TooltipDataHandlerMixin and ClearHandlerInfo call

r30:

- Add AF.AttachTransientScrollBar (template-free fade-in/out scroll bar with inactivity fade and drag hold)
- Add AF.CreateTreeList (scrollable tree list: pooled rows, accent highlight, chevron toggles, animated expand/collapse, compact icon-only mode; expansion state is shared between compact and expanded presentations with a single scroll offset)
- Add AF.CreateSidebarRail (auto-hide sidebar rail wrapping a tree list: hover expand/collapse, presentation-width publication, content inset helpers)
- Add Bag_* adaptive icons for consumable subclasses (Potions, Flasks, Food, Bandages, Elixirs) and every equipment slot (22 Bag_Slot_* icons), so bag sidebar categories no longer fall back to a generic Equipment icon
