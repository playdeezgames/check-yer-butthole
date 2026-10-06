class Display{
    static clear(){
        Utility.removeChildren(document.body);
    }
    static addSimpleChild(tagName, textContent){
        return Utility.addSimpleChild(document.body, tagName, textContent);
    }
    static addButton(textContent, clickHandler){
        let button = Utility.addSimpleChild(document.body, "button", textContent);
        button.addEventListener("click", clickHandler);
        return button;
    }
    static addGameMenuButton(){
        Display.addButton("Game Menu", GameMenu.run);
    }
}