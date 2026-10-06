class ConfirmAbandon{
    static run(){
        Display.clear();
        Display.addSimpleChild("h1", "Are you sure you want to abandon the game?")
        Display.addButton("Yes", ConfirmAbandon.confirm);
        Display.addButton("No", ConfirmAbandon.cancel);
    }
    static confirm(){
        World.abandon();
        Utility.abandonGame();
        MainMenu.run();
    }
    static cancel(){
        GameMenu.run();
    }
}