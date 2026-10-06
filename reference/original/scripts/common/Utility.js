class Utility{
    static removeChildren(element){
        while(element.firstChild){
            element.removeChild(element.firstChild);
        }
    }
    static addSimpleChild(element, tagName, textContent){
        let child = document.createElement(tagName);
        if(textContent != null){
            child.textContent=textContent;
        }
        element.appendChild(child);
        return child;
    }
    static saveGame(){
        localStorage.setItem(STORAGE_WORLD_DATA, JSON.stringify(worldData));
    }
    static loadGame(){
        worldData = JSON.parse(localStorage.getItem(STORAGE_WORLD_DATA));
        if(worldData==null){
            World.abandon();
        }
    }
    static abandonGame(){
        localStorage.removeItem(STORAGE_WORLD_DATA);
    }
    static roll(minimum, maximum){
        return Math.floor(Math.random() * (maximum - minimum + 1));
    }
}