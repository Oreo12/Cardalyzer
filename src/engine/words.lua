-- Every word the engine shows players: button labels, panel text, messages,
-- the questions it asks and how it describes effects. rules.ui.words
-- renames any of them (for a game's own terms, or a translation):
--
--   ui = { words = { playAll = "Deploy all ({n})", endTurn = "Pass",
--                    ["effect.draw"] = "Draw {n} cards" } }
--
-- An effect keyword's description is renamed with "effect.<keyword>" ({n}
-- is the amount); left out, the keyword describes itself.
--
-- {name} in a text is filled in when it's shown. A word can also be a
-- function(vars) returning the text.
local Words = {}

Words.DEFAULT = {
  -- the info panel
  notStarted = "Press New Game to set up a game.",
  turnLine = "Turn {n} · {name} to play",
  phaseLine = "Turn {n} · {name} · {phase}",
  nextPhase = "{phase} →",
  notThisPhase = "That can't be done in the {phase} phase.",
  wins = "{name} wins!",
  ["and"] = " and ",
  score = " · {n} points",
  scoreOne = " · {n} point",
  pool = "{n} {label} left",
  piles = "Deck {deck} · Discard {discard}",
  goalsCount = " · {label} {done}/{total}",
  settings = "Settings",
  newGame = "New Game",
  yourKit = "Your {kit}",
  out = ": out",
  -- the corner
  rulebooks = "Rulebooks",
  tidy = "Tidy table",
  -- the action bar
  playAll = "Play all ({n})",
  endTurn = "End Turn",
  attack = "Attack {name} ({n} {resource})",
  destroy = "Destroy {card} ({n})",
  scrap = "Scrap {card}: {effects}",
  use = "Use {card}",
  call = "Call {card}",
  setAsideFrom = "Put a card from your hand in your {area}",
  useWith = "Use {card}: {text}",
  complete = "Complete {card}",
  yourGoals = "Your {label}: {list}",
  skip = "Skip / done",
  done = "Done",
  more = " (+{n} more)",
  buy = "Buy · {n}",
  defeat = "Defeat · {n}",
  hire = "Hire · {n}",
  defeated = "{name} defeated {card}: {effects}",
  mustDefeat = "{card} can't be bought: defeat it with {resource}.",
  defeatUpTo = "Defeat a card costing {n} or less for free",
  -- the New Game menu
  setupTitle = "New Game",
  players = "Players",
  startingHands = "Starting hands",
  startingDecks = "Starting decks",
  standard = "Standard",
  sets = "Sets",
  supply = "Supply",
  playGame = "Play Game",
  tutorial = "Tutorial",
  close = "Close",
  hide = "Hide",
  hideUI = "Hide UI",
  showUI = "Show Cardalyzer",
  showPanel = "Show {name}",
  result = "result",
  yourChoice = "your choice",
  menus = "Menus",
  middle = "Middle",
  left = "Left",
  right = "Right",
  top = "Top",
  -- the kit menu
  choose = "Choose",
  premade = "Premade",
  random = "Random",
  custom = "Custom",
  saveAndBack = "Save and go back",
  cancel = "Cancel",
  kitRandomNote = "When the game starts you get a random premade {kit}, one nobody else picked while there are any left.",
  kitCustomNote = "Hover over a choice to see what it is. Anything you leave unpicked is picked at random when the game starts.",
  -- Settings
  uiSize = "UI size",
  actionBar = "Action bar",
  up = "Up",
  down = "Down",
  reset = "Reset",
  -- game over and the tutorial
  playAgain = "Play Again?",
  back = "Back",
  next = "Next",
  hideButton = "Hide button",
  page = "Page {n} of {total}",
  -- messages
  isOut = "{name} is out.",
  removedHands = "Removed the table's own seats ({colors}): Cardalyzer seats its players itself.",
  scrappedFromRow = "{name} scrapped {card} from the market row.",
  completed = "{name} completed {card}.",
  event = "Event: {card}. {effects}",
  reveals = "{name} reveals {card}: {effects}",
  unaffected = "{name} is unaffected.",
  ally = "{card} ally: {effects}",
  tutorialHidden = "Tutorial button hidden. Type !tutorial in chat to bring it back.",
  hostOnlyNewGame = "Only the host can start a new game.",
  hostOnlyPlayers = "Only the host can change the number of players.",
  hostOnlySets = "Only the host can choose the sets.",
  hostOnlyKits = "Only the host can choose the starting decks.",
  hostOnlyHands = "Only the host can change how many cards are dealt.",
  hostOnlySupply = "Only the host can choose the supply.",
  takeASeat = "Take a seat to play.",
  notStartedYet = "The game hasn't started.",
  gameOver = "The game is over.",
  othersTurn = "It's {name}'s turn.",
  firstDo = "First: {what}.",
  notInHand = "That card isn't in your hand.",
  handEmpty = "Your hand is empty.",
  cantBuy = "That card can't be bought.",
  notEnough = "Not enough {resource}: {card} costs {n}.",
  notInPlay = "That card isn't in play.",
  notInRow = "That card isn't in the market row.",
  pickOpponent = "Pick an opponent to attack.",
  nothingToAttack = "You have no {resource} to attack with.",
  baseNotInPlay = "That base isn't in play.",
  cantBeAttacked = "{card} can't be attacked.",
  guardsFirst = "Destroy their guard bases first.",
  needs = "{card} needs {n} {resource}.",
  alreadyOut = "{name} is already out.",
  nothingToChoose = "There's nothing to choose.",
  notAnOption = "That isn't one of the options.",
  chooseFirst = "You have to choose first: {what}.",
  finishFirst = "Finish this first: {what}.",
  cantUse = "That can't be used now.",
  notYourGoal = "That isn't one of your goals.",
  notYet = "You can't complete that yet.",
  -- questions (prompts)
  chooseOne = "Choose one",
  chooseCard = "Choose a card",
  reactTo = "{name} played {card}: {effects}. Reveal a reaction?",
  reactToAttack = "{name} attacks you: {effects}. Reveal a reaction?",
  reveal = "Reveal {card}",
  noReveal = "Don't reveal",
  scrapFrom = "Scrap {n} {cards} from {where}",
  scrapUpTo = "Scrap up to {n} {cards} from {where}",
  discardN = "Discard {n} {cards}",
  discardUpTo = "Discard up to {n} {cards}",
  scrapRow = "Scrap up to {n} {cards} from the market row",
  destroyUpTo = "Destroy up to {n} {bases}",
  returnUpTo = "Return up to {n} {bases} to its owner's hand",
  whereGoes = "Where should {card} go?",
  topOfDeck = "Top of your deck",
  yourDiscard = "Your discard pile",
  chooseOpponent = "Choose an opponent",
  chooseOpponentDiscard = "Choose an opponent to discard {n} {cards} next turn",
  takeFree = "Take {what}{limit} from {where} for free{dest}",
  aCard = "a card",
  aType = "a {type}",
  costLimit = " costing {n} or less",
  theMarket = "the market",
  ontoDeck = ", onto your deck",
  intoHand = ", into your hand",
  yourHand = "your hand",
  yourDiscardPile = "your discard pile",
  theMarketRow = "the market row",
  ["or"] = " or ",
  card = "card",
  cards = "cards",
  base = "base",
  bases = "bases",
}

-- The text for `key`, from rules.ui.words or the default, with {vars} filled in.
function Words.say(rules, key, vars)
  local own = rules and rules.ui and rules.ui.words and rules.ui.words[key]
  local word = own ~= nil and own or Words.DEFAULT[key]
  if word == nil then return key end
  if type(word) == "function" then return word(vars or {}) end
  return (word:gsub("{(%w+)}", function(name)
    local v = vars and vars[name]
    return v ~= nil and tostring(v) or "{" .. name .. "}"
  end))
end

-- "1 card" / "2 cards", in the game's words.
function Words.count(rules, n, one, many)
  return n .. " " .. Words.say(rules, n == 1 and one or many)
end

return Words
