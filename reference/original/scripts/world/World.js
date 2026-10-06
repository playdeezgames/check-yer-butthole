class World{
    static getAvatarCharacter(){
        if(worldData.avatarCharacterId!=null){
            return new Character(worldData, worldData.avatarCharacterId);
        }
        return null;
    }
    static setAvatarCharacter(character){
        worldData.avatarCharacterId = character.getId();
    }
    static hasAvatar(){
        return World.getAvatarCharacter() != null;
    }
    static start(name){
        if(name==null || name.trim()===''){
            name="n00b";
        }
        let character = World.createCharacter(CHARACTERTYPE_N00B);
        character.setName(name);
        World.setAvatarCharacter(character);
    }
    static createCharacter(characterType){
        let characterId = worldData.characters.length;
        let characterData = {};
        worldData.characters.push(characterData);
        let character= new Character(worldData, characterId);
        CharacterType.initialize(characterType, character);
        AdvancementType.initialize(character);
        return character;
    }
    static addMessage(message){
        worldData.messages.push(message);
    }
    static getMessages(){
        return worldData.messages;
    }
    static clearMessages(){
        worldData.messages=[];
    }
    static abandon(){
        worldData = {
            characters:[],
            messages:[]
        };
    }
};