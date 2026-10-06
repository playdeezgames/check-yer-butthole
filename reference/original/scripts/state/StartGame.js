const CHARACTER_NAME="characterName";
class StartGame{
    static run(){
        Display.clear();
        Display.addSimpleChild("h1", "Start Game");
        let paragraph = Display.addSimpleChild("p","");
        Utility.addSimpleChild(paragraph, "span", "Character Name:");
        let textBox = Utility.addSimpleChild(paragraph, "input");
        textBox.id=CHARACTER_NAME;
        Display.addButton("Cancel", StartGame.cancel);
        Display.addButton("EMBARK!", StartGame.embark);
    }
    static cancel(){
        MainMenu.run();
    }
    static embark(){
        let textBox = document.getElementById(CHARACTER_NAME);
        World.start(textBox.value);
        Neutral.run();
    }
}