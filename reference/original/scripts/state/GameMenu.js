class GameMenu{
    static run(){
        Display.clear();
        Display.addSimpleChild("h1", "Game Menu");
        Display.addButton("Continue Game", GameMenu.continueGame);
        Display.addButton("Abandon Game", GameMenu.abandonGame);
    }
    static continueGame(){
        Neutral.run();
    }
    static abandonGame(){
        ConfirmAbandon.run();
    }
}