// Definizione dei 5 pin analogici (disponibili da A0 ad A6 su MKR WiFi 1010)
const int numSensors = 5;
const int sensorPins[numSensors] = {A1, A2, A3, A4, A6};

void setup() {
  Serial.begin(9600);
  // Attesa per dare tempo al Plotter Seriale di avviarsi senza bloccare il codice
  delay(1500); 
  
  // Imposta la risoluzione ADC a 12 bit (valori da 0 a 4095)
  analogReadResolution(12);
}

void loop() {
  float voltages[numSensors];
  
  // Legge e converte i 5 sensori in tensione (0 - 5V)
  for (int i = 0; i < numSensors; i++) {
    int sensorValue = analogRead(sensorPins[i]);
    voltages[i] = sensorValue * (5 / 4095.0);
  }
  
  // Stampa formattata per il Plotter Seriale (gli indici partono da 0!)
  Serial.print("S1:");
  Serial.print(voltages[0], 2);
  Serial.print(",");
  
  Serial.print("S2:");
  Serial.print(voltages[1], 2);
  Serial.print(",");
  
  Serial.print("S3:");
  Serial.print(voltages[2], 2);
  Serial.print(",");
  
  Serial.print("S4:");
  Serial.print(voltages[3], 2);
  Serial.print(",");
  
  Serial.print("S5:");
  Serial.println(voltages[4], 2); // println chiude la riga del grafico
  
  delay(100); // Frequenza di campionamento di 10 Hz
}