class MainMenu{
    static run(){
        Display.clear();
        Display.addSimpleChild("h1", "Check Yer B*tthole, THE GAME");
        Display.addSimpleChild("h2", "A production of TheGrumpyGameDev");
        if(World.hasAvatar()){
            Display.addButton("Continue", MainMenu.continueGame);
        }else{
            Display.addButton("Start", MainMenu.startGame);
        }
    }
    static continueGame(){
        Neutral.run();
    }
    static startGame(){
        StartGame.run();
    }
}